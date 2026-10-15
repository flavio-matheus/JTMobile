import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Faixa de áudio exibida (Hz) e resolução do FFT.
const int kWfNfft = 4096;
const double kWfSampleRate = 12000.0;
const double kWfBinHz = kWfSampleRate / kWfNfft; // ≈ 2,93 Hz
const double kWfMaxHz = 3200.0;
final int kWfBins = (kWfMaxHz / kWfBinHz).floor();
const int kWfRows = 320;

/// Paleta no estilo WSJT-X/JTDX (azul -> ciano -> verde -> amarelo -> vermelho -> branco).
Uint32List buildPalette() {
  final p = Uint32List(256);
  const stops = <(double, int, int, int)>[
    (0.00, 0, 0, 24),
    (0.20, 0, 24, 140),
    (0.38, 0, 150, 200),
    (0.55, 0, 200, 60),
    (0.72, 240, 230, 0),
    (0.88, 255, 80, 0),
    (1.00, 255, 255, 255),
  ];
  for (var i = 0; i < 256; i++) {
    final x = i / 255.0;
    var k = 0;
    while (k < stops.length - 2 && x > stops[k + 1].$1) {
      k++;
    }
    final a = stops[k], b = stops[k + 1];
    final t = ((x - a.$1) / (b.$1 - a.$1)).clamp(0.0, 1.0);
    final r = (a.$2 + (b.$2 - a.$2) * t).round();
    final g = (a.$3 + (b.$3 - a.$3) * t).round();
    final bl = (a.$4 + (b.$4 - a.$4) * t).round();
    // RGBA little-endian: 0xAABBGGRR
    p[i] = (0xFF << 24) | (bl << 16) | (g << 8) | r;
  }
  return p;
}

/// Buffer circular de linhas de espectro (mais nova no topo na imagem).
class WaterfallBuffer {
  WaterfallBuffer() : _data = Uint8List(kWfRows * kWfBins), _times = List<int>.filled(kWfRows, 0);

  final Uint8List _data; // magnitudes normalizadas 0..255
  final List<int> _times; // ms desde a época, por linha
  int _head = 0; // próxima linha a escrever
  int count = 0;
  double _floor = -100; // estimativa do piso de ruído (dB)
  bool _floorInit = false;
  final Uint32List _palette = buildPalette();
  final Uint32List _pixels = Uint32List(kWfRows * kWfBins);

  /// [db] contém ao menos kWfBins valores de potência em dB (bin k = k * kWfBinHz).
  void pushRow(Float32List db, int timeMs, {required bool auto, required double gain, required double zero}) {
    // Piso = mediana aproximada via média de percentil baixo dos bins
    final sorted = Float32List.fromList(db.sublist(0, kWfBins))..sort();
    final median = sorted[kWfBins ~/ 2];
    if (!_floorInit) {
      _floor = median;
      _floorInit = true;
    } else {
      _floor += (median - _floor) * 0.05;
    }
    // range: 12..60 dB conforme ganho (0..1); zero desloca o piso (-15..+15 dB)
    final range = auto ? 45.0 : (70.0 - 55.0 * gain);
    final base = auto ? _floor - 2.0 : _floor + (zero - 0.5) * 30.0 - 2.0;
    final off = _head * kWfBins;
    for (var k = 0; k < kWfBins; k++) {
      final v = ((db[k] - base) / range).clamp(0.0, 1.0);
      _data[off + k] = (v * 255).round();
    }
    _times[_head] = timeMs;
    _head = (_head + 1) % kWfRows;
    if (count < kWfRows) count++;
  }

  /// Hora (ms) da linha [i] contada do topo (0 = mais nova). Retorna 0 se não existir.
  int timeOfRow(int i) {
    if (i >= count) return 0;
    return _times[(_head - 1 - i + kWfRows * 2) % kWfRows];
  }

  /// Converte para imagem (largura kWfBins x kWfRows, linha 0 = mais nova).
  Future<ui.Image> toImage() async {
    for (var i = 0; i < kWfRows; i++) {
      if (i >= count) {
        for (var k = 0; k < kWfBins; k++) {
          _pixels[i * kWfBins + k] = _palette[0];
        }
        continue;
      }
      final src = ((_head - 1 - i + kWfRows * 2) % kWfRows) * kWfBins;
      final dst = i * kWfBins;
      for (var k = 0; k < kWfBins; k++) {
        _pixels[dst + k] = _palette[_data[src + k]];
      }
    }
    final bytes = Uint8List.view(_pixels.buffer);
    return _decode(bytes);
  }

  Future<ui.Image> _decode(Uint8List bytes) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, kWfBins, kWfRows, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }
}
