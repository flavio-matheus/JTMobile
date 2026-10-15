/// Monitor de áudio: reproduz o áudio recebido do rádio no **alto-falante do celular**.
///
/// Muitos operadores gostam de **ouvir o "assobio"** dos modos digitais (FT8/FT4...), por exemplo para
/// perceber a propagação ou a ocupação da banda. Quando ativado ([AudioMonitor.start]), cada pacote
/// PCM de RX (48 kHz, 16 bit, mono) é enviado ao código nativo (`MainActivity.kt`, canal
/// `br.poinsp.ft_mobile/monitor`), que o toca por um `AudioTrack` em modo *stream*, no volume de
/// **mídia** do celular multiplicado pelo ganho do monitor.
///
/// Observações de projeto:
///  * Este caminho é **independente** da decodificação: ele só espelha o áudio; falhas aqui nunca
///    afetam o decodificador (todas as chamadas são protegidas).
///  * O monitor é desligado durante a TX (o rádio não envia RX útil) e o ganho pode ser ajustado em tempo real.
///  * A latência do monitor (~100–200 ms de buffer) não importa para a audição.
///  * Cuidado com **realimentação** se o celular estiver perto do microfone do rádio.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Reprodutor do áudio recebido (implementação nativa ou falsa em testes).
abstract class AudioMonitor {
  /// `true` enquanto o monitor está ligado.
  bool get running;

  /// Liga o monitor para áudio PCM mono de [sampleRate] Hz com ganho [volume] (0..1).
  Future<void> start({required int sampleRate, required double volume});

  /// Define o ganho (0..1) sem reiniciar.
  Future<void> setVolume(double volume);

  /// Envia um pacote de áudio (PCM s16le mono) para reprodução. Chamadas com o monitor parado são ignoradas.
  void write(Int16List pcm);

  /// Desliga o monitor e libera o AudioTrack.
  Future<void> stop();
}

/// Implementação real (Android) via canal de plataforma.
class NativeAudioMonitor implements AudioMonitor {
  static const MethodChannel _ch = MethodChannel('br.poinsp.ft_mobile/monitor');

  bool _running = false;

  @override
  bool get running => _running;

  @override
  Future<void> start({required int sampleRate, required double volume}) async {
    try {
      await _ch.invokeMethod<void>('start', {'rate': sampleRate, 'volume': volume});
      _running = true;
    } on MissingPluginException {
      _running = false; // fora do Android: sem monitor
    } catch (_) {
      _running = false;
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    if (!_running) return;
    try {
      await _ch.invokeMethod<void>('volume', {'volume': volume});
    } catch (_) {}
  }

  @override
  void write(Int16List pcm) {
    if (!_running || pcm.isEmpty) return;
    // Envio "dispara e esquece": o canal copia os bytes; a leitura não precisa de resposta.
    _ch.invokeMethod<void>('write', {'pcm': Uint8List.view(pcm.buffer, pcm.offsetInBytes, pcm.lengthInBytes)}).catchError((Object _) {});
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      await _ch.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
