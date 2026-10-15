// Teste de integração do Engine com o simulador de rádio e um codec falso: verifica que o monitor do
// alto-falante recebe o áudio de RX **e o áudio de TX** (o operador precisa ouvir o que está transmitindo).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jtmobile/core/ftx_native.dart';
import 'package:jtmobile/core/settings.dart';
import 'package:jtmobile/engine/alerts.dart';
import 'package:jtmobile/engine/audio_monitor.dart';
import 'package:jtmobile/engine/engine.dart';

/// Codec sem DSP real: gera um sinal constante e nenhuma decodificação.
class FakeCodec extends FtxCodec {
  @override
  List<RawDecode> decode(Float32List samples12k, FtxProtocol proto, {double fMin = 100, double fMax = 3100}) => [];
  @override
  Uint8List? encode(String text, FtxProtocol proto) => Uint8List(proto.numTones);
  @override
  Float32List synth(Uint8List tones, FtxProtocol proto, double f0, int rate) =>
      Float32List(tones.length * (0.5 + rate * proto.symbolSeconds).floor())..fillRange(0, tones.length * (0.5 + rate * proto.symbolSeconds).floor(), 0.5);
  @override
  Float32List spectrum(Float32List samples, int nfft) => Float32List(nfft ~/ 2)..fillRange(0, nfft ~/ 2, -100);
  @override
  Decimator newDecimator() => _Dec();
}

class _Dec implements Decimator {
  @override
  Float32List process(Int16List input) => Float32List(input.length ~/ 4);
  @override
  void dispose() {}
}

class _QuietPlayer implements AlertPlayer {
  @override
  Future<void> play(AlertKind kind) async {}
  @override
  Future<void> vibrate(AlertKind kind) async {}
}

/// Monitor falso: conta as amostras recebidas, separando RX de TX pelo estado do motor.
class FakeMonitor implements AudioMonitor {
  Engine? engine;
  bool _running = false;
  int rxSamples = 0;
  int txSamples = 0;
  double? lastVolume;

  @override
  bool get running => _running;
  @override
  Future<void> start({required int sampleRate, required double volume}) async {
    _running = true;
    lastVolume = volume;
  }

  @override
  Future<void> setVolume(double volume) async => lastVolume = volume;
  @override
  void write(Int16List pcm) {
    final e = engine;
    if (e != null && (e.transmitting || e.tuning)) {
      txSamples += pcm.length;
    } else {
      rxSamples += pcm.length;
    }
  }

  @override
  Future<void> stop() async => _running = false;
}

/// Cria um relógio falso que fica ~1,2 s antes do próximo início de slot de 15 s (FT8) e devolve também
/// a paridade (0/1) do slot que vai começar.
({DateTime Function() clock, int parity}) clockBeforeSlot() {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final boundary = ((nowMs + 1500) ~/ 15000 + 1) * 15000;
  final offset = boundary - 1200 - nowMs;
  return (clock: () => DateTime.now().add(Duration(milliseconds: offset)), parity: (boundary ~/ 15000) % 2);
}

Settings baseSettings({required bool monitorTx}) => Settings.memory()
  ..callsign = 'PY2XYZ'
  ..grid = 'GG66'
  ..radioKind = RadioKind.simulator
  ..monitorSpeaker = true
  ..monitorTx = monitorTx;

void main() {
  test('com "ouvir meu áudio de TX" ligado, o monitor recebe o áudio de RX e o de TX', () async {
    final c = clockBeforeSlot();
    final mon = FakeMonitor();
    final engine = Engine(
      settings: baseSettings(monitorTx: true),
      codec: FakeCodec(),
      clock: c.clock,
      monitor: mon,
      alerts: AlertCenter(player: _QuietPlayer()),
    );
    mon.engine = engine;
    await engine.start();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(mon.running, isTrue, reason: 'o monitor liga quando o rádio conecta');
    expect(mon.rxSamples, greaterThan(0), reason: 'áudio de RX espelhado');

    engine.txParity = c.parity;
    engine.setTxEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 3000));
    expect(engine.transmitting, isTrue);
    expect(mon.txSamples, greaterThan(960), reason: 'áudio de TX espelhado no alto-falante');

    engine.haltTx();
    engine.dispose();
  });

  test('com a opção desligada, o áudio de TX não vai ao alto-falante', () async {
    final c = clockBeforeSlot();
    final mon = FakeMonitor();
    final engine = Engine(
      settings: baseSettings(monitorTx: false),
      codec: FakeCodec(),
      clock: c.clock,
      monitor: mon,
      alerts: AlertCenter(player: _QuietPlayer()),
    );
    mon.engine = engine;
    await engine.start();
    engine.txParity = c.parity;
    engine.setTxEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 3000));
    expect(engine.transmitting, isTrue);
    expect(mon.txSamples, 0);

    engine.haltTx();
    engine.dispose();
  });
}
