import 'dart:async';
import 'dart:typed_data';

import 'civ.dart';

enum LinkStatus { disconnected, connecting, connected, error }

/// Abstração do enlace com o rádio: áudio de RX/TX (PCM 16 bit mono 48 kHz) e CI-V.
abstract class RadioLink {
  static const int audioRate = 48000;

  LinkStatus get status;
  String get statusText;
  RadioState get state;

  /// Fluxo de áudio recebido do rádio: PCM s16le, mono, 48 kHz.
  Stream<Int16List> get rxAudio;

  /// Notifica mudanças de estado/estatísticas.
  Stream<void> get changes;

  Future<void> connect();
  Future<void> disconnect();

  /// Liga/desliga o PTT (via CI-V).
  void setPtt(bool on);

  void setFrequency(int hz);
  void setUsbData();

  /// Envia áudio de TX: PCM s16le mono 48 kHz. O chamador deve respeitar o ritmo de tempo real.
  void sendTxAudio(Int16List pcm);

  /// Envia comando CI-V cru.
  void sendCiv(Uint8List frame);

  /// Latência de ida e volta (ms), se conhecida.
  int? get pingMs;
  int get lostPackets;
}
