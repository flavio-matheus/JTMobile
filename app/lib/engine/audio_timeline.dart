/// Linha do tempo do áudio recebido: converte "contagem de amostras" em "hora UTC de captura".
///
/// ## Por que existe
/// A decodificação FT8/FT4 depende de saber **exatamente quando** cada amostra foi capturada em
/// relação ao início do período (slot). Se simplesmente usássemos a hora de *chegada* de cada
/// pacote UDP, o *jitter* de rede e pausas da interface (GC, redesenho da waterfall) deslocariam
/// o áudio e degradariam o DT e a sensibilidade.
///
/// ## Como funciona
/// * O rádio envia amostras a uma taxa constante (48 kHz): a hora relativa entre amostras é
///   conhecida (`k / rate`). Só falta o deslocamento absoluto, `offset` (UTC da amostra 0).
/// * Para cada pacote, `arrival − (amostras_até_o_fim / rate)` é uma estimativa de `offset`
///   **somada ao atraso daquele pacote**. O atraso nunca é negativo, então o **mínimo** em uma
///   janela deslizante (≈10 s) estima o `offset` verdadeiro + o atraso mínimo de rede.
/// * O `offset` segue o mínimo com variação limitada (*slew*) para absorver o desvio entre o
///   relógio do rádio e o do celular (dezenas de ppm) sem saltos.
/// * Perda de pacotes: se o atraso medido fica alto de forma **persistente** (não é jitter, que
///   volta ao normal no pacote seguinte), conta-se que amostras foram perdidas e o chamador recebe
///   `pad` amostras de silêncio para inserir antes do pacote — mantendo o alinhamento temporal.
///
/// A classe é pura (sem relógio interno): todos os tempos são passados por parâmetro, o que a
/// torna determinística e testável (`test/audio_timeline_test.dart`).
library;

/// Resultado do processamento de um pacote.
class ChunkTiming {
  const ChunkTiming(this.startUs, this.padSamples);

  /// Hora UTC (µs desde a época) da **primeira amostra** do pacote.
  final int startUs;

  /// Nº de amostras de silêncio a inserir **antes** do pacote (perda detectada), normalmente 0.
  final int padSamples;
}

class AudioTimeline {
  AudioTimeline({this.rate = 48000, this.windowSeconds = 10, this.lossGapUs = 60000, this.lossRun = 3});

  /// Taxa de amostragem do áudio de entrada (Hz).
  final int rate;

  /// Largura da janela de mínimos (s).
  final int windowSeconds;

  /// Atraso extra persistente (µs) a partir do qual se considera perda de amostras.
  final int lossGapUs;

  /// Nº de pacotes consecutivos acima de [lossGapUs] para declarar perda.
  final int lossRun;

  int _count = 0; // amostras já contabilizadas (inclui preenchimento)
  double? _offsetUs; // UTC (µs) da amostra 0
  int _highRun = 0;

  // Mínimos por "balde" de 1 s: (índice do balde, menor valor observado).
  final List<(int, double)> _buckets = [];

  /// Total de amostras contabilizadas (inclui silêncio inserido por perdas).
  int get samples => _count;

  /// Deslocamento atual (UTC µs da amostra 0), ou `null` antes do primeiro pacote.
  double? get offsetUs => _offsetUs;

  /// Reinicia (ex.: ao reconectar o rádio).
  void reset() {
    _count = 0;
    _offsetUs = null;
    _highRun = 0;
    _buckets.clear();
  }

  /// Processa um pacote de [n] amostras que chegou em [arrivalUs] (UTC µs).
  ChunkTiming onChunk(int arrivalUs, int n) {
    final endIdx = _count + n;
    final raw = arrivalUs - endIdx * 1e6 / rate; // offset + atraso deste pacote

    // atualiza mínimos por balde de 1 s
    final bucket = arrivalUs ~/ 1000000;
    if (_buckets.isNotEmpty && _buckets.last.$1 == bucket) {
      if (raw < _buckets.last.$2) _buckets[_buckets.length - 1] = (bucket, raw);
    } else {
      _buckets.add((bucket, raw));
    }
    while (_buckets.isNotEmpty && _buckets.first.$1 < bucket - windowSeconds) {
      _buckets.removeAt(0);
    }
    var minimum = raw;
    for (final b in _buckets) {
      if (b.$2 < minimum) minimum = b.$2;
    }

    if (_offsetUs == null) {
      _offsetUs = minimum;
    } else {
      final diff = minimum - _offsetUs!;
      if (diff < 0) {
        _offsetUs = minimum; // chegada mais cedo que o mínimo anterior: adota de imediato
      } else if (diff > 150000) {
        _offsetUs = minimum; // salto grande (pausa longa/reconexão): reancora
        _highRun = 0;
      } else {
        // acompanha o aumento lentamente (desvio de relógio): no máx. 150 µs por pacote
        _offsetUs = _offsetUs! + (diff > 150 ? 150 : diff);
      }
    }

    // detecção de perda: atraso persistentemente acima do mínimo
    var pad = 0;
    final extra = raw - _offsetUs!;
    if (extra > lossGapUs) {
      _highRun++;
      if (_highRun >= lossRun) {
        pad = (extra * rate / 1e6).round().clamp(0, rate * 2);
        _highRun = 0;
      }
    } else {
      _highRun = 0;
    }
    _count += pad;
    final startIdx = _count;
    _count += n;
    return ChunkTiming((_offsetUs! + startIdx * 1e6 / rate).round(), pad);
  }
}
