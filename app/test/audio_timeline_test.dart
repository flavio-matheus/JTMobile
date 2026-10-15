import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:jtmobile/engine/audio_timeline.dart';

/// Simula pacotes de áudio de 20 ms (960 amostras a 48 kHz) chegando com atraso fixo + jitter.
void main() {
  const rate = 48000;
  const chunk = 960; // 20 ms
  const chunkUs = 20000;

  test('estimativa de offset converge apesar do jitter (0..30 ms) e atraso base de 50 ms', () {
    final tl = AudioTimeline(rate: rate);
    final rnd = Random(1);
    const trueStart = 1000000000; // hora UTC (µs) da amostra 0
    const baseDelay = 50000;
    for (var i = 0; i < 1000; i++) {
      final endTrue = trueStart + (i + 1) * chunkUs; // fim real do pacote i
      final arrival = endTrue + baseDelay + rnd.nextInt(30000);
      final t = tl.onChunk(arrival, chunk);
      expect(t.padSamples, 0, reason: 'sem perdas, i=$i');
      if (i > 600) {
        // a hora estimada deve ser a verdadeira + o atraso mínimo (50 ms), com erro de poucos ms
        final expected = trueStart + i * chunkUs + baseDelay;
        expect((t.startUs - expected).abs(), lessThan(4000), reason: 'i=$i');
      }
    }
  });

  test('perda de 100 ms de áudio é compensada com silêncio e o alinhamento é recuperado', () {
    final tl = AudioTimeline(rate: rate);
    const trueStart = 2000000000;
    const baseDelay = 30000;
    var padTotal = 0;
    var checked = false;
    for (var i = 0; i < 400; i++) {
      if (i >= 200 && i < 205) continue; // pacotes 200..204 (100 ms) nunca chegam
      final arrival = trueStart + (i + 1) * chunkUs + baseDelay;
      final t = tl.onChunk(arrival, chunk);
      padTotal += t.padSamples;
      if (i >= 230) {
        final expected = trueStart + i * chunkUs + baseDelay;
        expect((t.startUs - expected).abs(), lessThan(6000), reason: 'i=$i após a perda');
        checked = true;
      }
    }
    expect(padTotal, inInclusiveRange(3000, 5000)); // ≈ 4800 amostras (100 ms)
    expect(checked, isTrue);
  });

  test('desvio de relógio de +50 ppm é acompanhado sem perdas falsas', () {
    final tl = AudioTimeline(rate: rate);
    const trueStart = 3000000000;
    var pads = 0;
    for (var i = 0; i < 6000; i++) {
      // o rádio produz amostras 50 ppm mais devagar: cada pacote leva 20 ms * (1 + 50e-6)
      final arrival = trueStart + ((i + 1) * chunkUs * (1 + 50e-6)).round() + 20000;
      pads += tl.onChunk(arrival, chunk).padSamples;
    }
    expect(pads, 0);
  });
}
