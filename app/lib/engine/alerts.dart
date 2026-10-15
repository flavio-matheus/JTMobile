/// Alertas ao operador: aviso **visual** (faixa no topo + piscar de borda), **sonoro** e **vibração**.
///
/// Disparados pelo motor quando:
///  * o app **começa a transmitir** ([AlertKind.txStart]);
///  * uma estação **responde/chama você** ([AlertKind.reply]);
///  * um **QSO é concluído** ([AlertKind.qsoComplete]);
///  * há uma orientação/aviso ([AlertKind.info], [AlertKind.warning]).
///
/// Os sons são **sintetizados em código** ([AlertSounds]) — sem arquivos de áudio no repositório — e
/// reproduzidos pelo Android via `AudioTrack` (canal nativo `br.poinsp.ft_mobile/alert`, veja
/// `MainActivity.kt`). Em testes, injete um [AlertPlayer] falso.
///
/// Os alertas respeitam as opções "Som" e "Vibração" das configurações e usam o volume de **mídia**
/// do celular (ajuste-o antes de operar).
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Tipo de alerta (define cor, ícone, som e padrão de vibração).
enum AlertKind { txStart, reply, qsoComplete, info, warning }

/// Um alerta exibido na interface.
class AppAlert {
  AppAlert(this.kind, this.title, this.body, this.time);
  final AlertKind kind;
  final String title;
  final String body;
  final DateTime time;
}

/// Reprodutor de som/vibração (implementação nativa ou falsa em testes).
abstract class AlertPlayer {
  Future<void> play(AlertKind kind);
  Future<void> vibrate(AlertKind kind);
}

/// Sons de alerta sintetizados (PCM 16 bit mono, 22,05 kHz).
class AlertSounds {
  const AlertSounds._();

  /// Taxa de amostragem dos sons.
  static const int sampleRate = 22050;

  /// Sequência de notas (frequência Hz, duração ms) de cada alerta.
  static const Map<AlertKind, List<(double, int)>> notes = {
    // TX: bip descendente curto ("saindo no ar")
    AlertKind.txStart: [(1046.5, 110), (784.0, 160)],
    // Resposta: acorde ascendente de três notas — inconfundível
    AlertKind.reply: [(784.0, 130), (987.8, 130), (1318.5, 330)],
    // QSO completo: arpejo de dó maior com nota final longa
    AlertKind.qsoComplete: [(523.3, 110), (659.3, 110), (784.0, 110), (1046.5, 420)],
    AlertKind.info: [(880.0, 120)],
    AlertKind.warning: [(440.0, 160), (330.0, 260)],
  };

  /// Gera o PCM (little-endian, 16 bit) do alerta [kind]. Cada nota tem ataque de 6 ms e decaimento
  /// exponencial, com um harmônico (2ª) para soar "de sino"; volume alto, porém sem saturar.
  static Uint8List pcm(AlertKind kind, {double volume = 0.85}) {
    final seq = notes[kind]!;
    final out = BytesBuilder();
    for (final (freq, ms) in seq) {
      final n = (sampleRate * ms / 1000).round();
      final attack = (sampleRate * 0.006).round();
      final b = ByteData(n * 2);
      for (var i = 0; i < n; i++) {
        final t = i / sampleRate;
        final env = (i < attack ? i / attack : 1.0) * exp(-3.2 * i / n);
        final s = (sin(2 * pi * freq * t) + 0.25 * sin(4 * pi * freq * t)) / 1.25;
        b.setInt16(i * 2, (s * env * volume * 32767).round().clamp(-32768, 32767), Endian.little);
      }
      out.add(b.buffer.asUint8List());
    }
    return out.toBytes();
  }

  /// Duração total (ms) do alerta.
  static int durationMs(AlertKind kind) => notes[kind]!.fold<int>(0, (a, n) => a + n.$2);
}

/// Implementação real: envia o PCM e o padrão de vibração ao código nativo (Android).
class NativeAlertPlayer implements AlertPlayer {
  static const MethodChannel _ch = MethodChannel('br.poinsp.ft_mobile/alert');

  /// Padrões de vibração (ms): espera, vibra, espera, vibra...
  static const Map<AlertKind, List<int>> _patterns = {
    AlertKind.txStart: [0, 120],
    AlertKind.reply: [0, 150, 90, 150, 90, 300],
    AlertKind.qsoComplete: [0, 120, 80, 120, 80, 120, 80, 400],
    AlertKind.info: [0, 60],
    AlertKind.warning: [0, 300, 120, 300],
  };

  @override
  Future<void> play(AlertKind kind) async {
    try {
      await _ch.invokeMethod<void>('playPcm', {'pcm': AlertSounds.pcm(kind), 'rate': AlertSounds.sampleRate});
    } on MissingPluginException {
      // fora do Android (testes/desktop): sem som
    } catch (_) {}
  }

  @override
  Future<void> vibrate(AlertKind kind) async {
    try {
      await _ch.invokeMethod<void>('vibrate', {'pattern': _patterns[kind]!});
    } on MissingPluginException {
      // sem vibração fora do Android
    } catch (_) {}
  }
}

/// Central de alertas: guarda o alerta atual (para a faixa na UI), dispara som/vibração e o
/// "flash" de borda, e descarta o alerta automaticamente após [autoDismiss].
class AlertCenter extends ChangeNotifier {
  AlertCenter({
    AlertPlayer? player,
    this.autoDismiss = const Duration(seconds: 8),
    this.holdImportant = const Duration(milliseconds: 3500),
  }) : _player = player ?? NativeAlertPlayer();

  final AlertPlayer _player;

  /// Tempo até a faixa desaparecer sozinha.
  final Duration autoDismiss;

  /// Tempo mínimo em que uma faixa de **resposta/QSO completo** não é substituída por avisos menos
  /// importantes (ex.: o início do TX logo em seguida) — para o operador conseguir ler.
  final Duration holdImportant;
  DateTime? _lockedUntil;

  /// Habilita o som (configuração do usuário).
  bool soundEnabled = true;

  /// Habilita a vibração (configuração do usuário).
  bool vibrateEnabled = true;

  /// Mostra a faixa (pop-up) no topo da tela. Desligado, o alerta ainda pode tocar/vibrar/piscar.
  bool bannerEnabled = true;

  /// Pisca a borda da tela a cada alerta.
  bool flashEnabled = true;

  /// Alerta em destaque (ou `null`).
  AppAlert? current;

  /// Incrementa a cada alerta: a UI usa para reiniciar a animação de "flash" da borda.
  int flashTick = 0;

  /// Histórico (mais recente por último; máx. 50) — útil para depuração e futura tela de eventos.
  final List<AppAlert> history = [];

  Timer? _timer;

  /// Mostra um alerta: atualiza a faixa, toca o som e vibra conforme as opções.
  void show(AlertKind kind, String title, [String body = '']) {
    final now = DateTime.now();
    final a = AppAlert(kind, title, body, now);
    // Avisos de menor prioridade não "roubam" a faixa de uma resposta recém-chegada.
    final lowPriority = kind == AlertKind.txStart || kind == AlertKind.info;
    final held = lowPriority && current != null && _lockedUntil != null && now.isBefore(_lockedUntil!);
    flashTick++;
    history.add(a);
    if (history.length > 50) history.removeAt(0);
    if (soundEnabled) _player.play(kind);
    if (vibrateEnabled) _player.vibrate(kind);
    if (!held && bannerEnabled) {
      current = a;
      _lockedUntil = (kind == AlertKind.reply || kind == AlertKind.qsoComplete) ? now.add(holdImportant) : null;
      _timer?.cancel();
      _timer = Timer(autoDismiss, dismiss);
    }
    notifyListeners();
  }

  /// Fecha a faixa de alerta.
  void dismiss() {
    _timer?.cancel();
    if (current != null) {
      current = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
