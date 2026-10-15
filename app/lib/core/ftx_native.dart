// Acesso (dart:ffi) à biblioteca nativa libftx_bridge.so (FT8/FT4 sobre ft8_lib).
import 'dart:ffi';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

enum FtxProtocol {
  ft8(0, 15.0, 79, 6.25, 0.16, 'FT8'),
  ft4(1, 7.5, 105, 20.8333, 0.048, 'FT4');

  const FtxProtocol(this.id, this.slotSeconds, this.numTones, this.toneSpacing, this.symbolSeconds, this.label);
  final int id;
  final double slotSeconds;
  final int numTones;
  final double toneSpacing;
  final double symbolSeconds;
  final String label;

  /// Largura de banda aproximada do sinal (Hz).
  double get bandwidth => toneSpacing * (this == ft8 ? 8 : 4);
}

final class _FtxDecodedC extends Struct {
  @Float()
  external double freqHz;
  @Float()
  external double dtSec;
  @Float()
  external double snrDb;
  @Int32()
  external int score;
  @Array(48)
  external Array<Uint8> text;
}

class RawDecode {
  RawDecode(this.freqHz, this.dtSec, this.snrDb, this.score, this.text);
  final double freqHz;
  final double dtSec;
  final double snrDb;
  final int score;
  final String text;
}

/// Interface do codec, para permitir substituir por um falso nos testes.
abstract class FtxCodec {
  List<RawDecode> decode(Float32List samples12k, FtxProtocol proto, {double fMin = 100, double fMax = 3100});

  /// Versão assíncrona (em outro isolate quando possível), para não travar a interface.
  Future<List<RawDecode>> decodeAsync(Float32List samples12k, FtxProtocol proto,
          {double fMin = 100, double fMax = 3100}) async =>
      decode(samples12k, proto, fMin: fMin, fMax: fMax);

  /// Texto -> tons. Retorna null se a mensagem for inválida.
  Uint8List? encode(String text, FtxProtocol proto);

  /// Tons -> áudio (amplitude 1.0) em [rate] Hz com frequência base [f0].
  Float32List synth(Uint8List tones, FtxProtocol proto, double f0, int rate);

  /// Espectro em dB de [nfft] amostras a 12 kHz (nfft/2 valores).
  Float32List spectrum(Float32List samples, int nfft);

  /// Cria um decimador 48 kHz -> 12 kHz.
  Decimator newDecimator();
}

abstract class Decimator {
  /// Converte PCM16 48 kHz em float 12 kHz.
  Float32List process(Int16List input);
  void dispose();
}

class FtxNative implements FtxCodec {
  FtxNative._(this._lib)
      : _decode = _lib.lookupFunction<
            Int32 Function(Pointer<Float>, Int32, Int32, Int32, Float, Float, Int32, Pointer<_FtxDecodedC>),
            int Function(Pointer<Float>, int, int, int, double, double, int, Pointer<_FtxDecodedC>)>('ftx_decode'),
        _encode = _lib.lookupFunction<Int32 Function(Pointer<Utf8>, Int32, Pointer<Uint8>),
            int Function(Pointer<Utf8>, int, Pointer<Uint8>)>('ftx_encode'),
        _synth = _lib.lookupFunction<Int32 Function(Pointer<Uint8>, Int32, Float, Int32, Pointer<Float>),
            int Function(Pointer<Uint8>, int, double, int, Pointer<Float>)>('ftx_synth'),
        _spectrum = _lib.lookupFunction<Int32 Function(Pointer<Float>, Int32, Pointer<Float>),
            int Function(Pointer<Float>, int, Pointer<Float>)>('ftx_spectrum'),
        _dec4New = _lib.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>('ftx_dec4_new'),
        _dec4Free = _lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('ftx_dec4_free'),
        _dec4 = _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Int16>, Int32, Pointer<Float>),
            int Function(Pointer<Void>, Pointer<Int16>, int, Pointer<Float>)>('ftx_dec4');

  // ignore: unused_field
  final DynamicLibrary _lib;
  final int Function(Pointer<Float>, int, int, int, double, double, int, Pointer<_FtxDecodedC>) _decode;
  final int Function(Pointer<Utf8>, int, Pointer<Uint8>) _encode;
  final int Function(Pointer<Uint8>, int, double, int, Pointer<Float>) _synth;
  final int Function(Pointer<Float>, int, Pointer<Float>) _spectrum;
  final Pointer<Void> Function() _dec4New;
  final void Function(Pointer<Void>) _dec4Free;
  final int Function(Pointer<Void>, Pointer<Int16>, int, Pointer<Float>) _dec4;

  static FtxNative? _instance;

  /// Carrega a biblioteca (Android). Retorna null se indisponível (ex.: testes no PC).
  static FtxNative? tryLoad() {
    if (_instance != null) return _instance;
    try {
      final lib = Platform.isAndroid ? DynamicLibrary.open('libftx_bridge.so') : DynamicLibrary.process();
      return _instance = FtxNative._(lib);
    } catch (_) {
      return null;
    }
  }

  @override
  List<RawDecode> decode(Float32List samples, FtxProtocol proto, {double fMin = 100, double fMax = 3100}) {
    const maxOut = 100;
    final inp = calloc<Float>(samples.length);
    final out = calloc<_FtxDecodedC>(maxOut);
    try {
      inp.asTypedList(samples.length).setAll(0, samples);
      final n = _decode(inp, samples.length, 12000, proto.id, fMin, fMax, maxOut, out);
      final res = <RawDecode>[];
      for (var i = 0; i < n; i++) {
        final d = out[i];
        final bytes = <int>[];
        for (var k = 0; k < 48; k++) {
          final c = d.text[k];
          if (c == 0) break;
          bytes.add(c);
        }
        res.add(RawDecode(d.freqHz, d.dtSec, d.snrDb, d.score, String.fromCharCodes(bytes)));
      }
      return res;
    } finally {
      calloc.free(inp);
      calloc.free(out);
    }
  }

  @override
  Future<List<RawDecode>> decodeAsync(Float32List samples, FtxProtocol proto, {double fMin = 100, double fMax = 3100}) {
    return Isolate.run(() => FtxNative.tryLoad()!.decode(samples, proto, fMin: fMin, fMax: fMax));
  }

  @override
  Uint8List? encode(String text, FtxProtocol proto) {
    final t = text.toUpperCase().toNativeUtf8();
    final tones = calloc<Uint8>(128);
    try {
      final n = _encode(t, proto.id, tones);
      if (n <= 0) return null;
      return Uint8List.fromList(tones.asTypedList(n));
    } finally {
      malloc.free(t);
      calloc.free(tones);
    }
  }

  @override
  Float32List synth(Uint8List tones, FtxProtocol proto, double f0, int rate) {
    final nSp = (0.5 + rate * proto.symbolSeconds).floor();
    final total = proto.numTones * nSp;
    final t = calloc<Uint8>(tones.length);
    final out = calloc<Float>(total);
    try {
      t.asTypedList(tones.length).setAll(0, tones);
      final n = _synth(t, proto.id, f0, rate, out);
      return Float32List.fromList(out.asTypedList(n < 0 ? 0 : n));
    } finally {
      calloc.free(t);
      calloc.free(out);
    }
  }

  @override
  Float32List spectrum(Float32List samples, int nfft) {
    final inp = calloc<Float>(nfft);
    final out = calloc<Float>(nfft ~/ 2);
    try {
      inp.asTypedList(nfft).setAll(0, samples.length >= nfft ? samples.sublist(0, nfft) : samples);
      final n = _spectrum(inp, nfft, out);
      return Float32List.fromList(out.asTypedList(n < 0 ? 0 : n));
    } finally {
      calloc.free(inp);
      calloc.free(out);
    }
  }

  @override
  Decimator newDecimator() => _NativeDecimator(this);
}

/// Decimador 48 kHz -> 12 kHz com buffers nativos **pré-alocados**.
///
/// Esta função roda ~50 vezes por segundo no caminho crítico do áudio de RX; evitar alocações
/// nativas a cada pacote reduz *jitter* e pressão sobre o coletor de lixo.
class _NativeDecimator implements Decimator {
  _NativeDecimator(this._n)
      : _state = _n._dec4New(),
        _in = calloc<Int16>(_cap),
        _out = calloc<Float>(_cap ~/ 4 + 8);

  static const int _cap = 8192; // amostras de entrada por chamada nativa
  final FtxNative _n;
  final Pointer<Void> _state;
  final Pointer<Int16> _in;
  final Pointer<Float> _out;

  @override
  Float32List process(Int16List input) {
    final res = <Float32List>[];
    for (var off = 0; off < input.length; off += _cap) {
      final len = (input.length - off) < _cap ? input.length - off : _cap;
      _in.asTypedList(len).setAll(0, Int16List.sublistView(input, off, off + len));
      final n = _n._dec4(_state, _in, len, _out);
      res.add(Float32List.fromList(_out.asTypedList(n)));
    }
    if (res.length == 1) return res.first;
    final total = res.fold<int>(0, (a, b) => a + b.length);
    final all = Float32List(total);
    var o = 0;
    for (final r in res) {
      all.setAll(o, r);
      o += r.length;
    }
    return all;
  }

  @override
  void dispose() {
    _n._dec4Free(_state);
    calloc.free(_in);
    calloc.free(_out);
  }
}
