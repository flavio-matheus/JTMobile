/// Abstração do enlace com o rádio.
///
/// O motor (`engine/engine.dart`) fala apenas com [RadioLink]; as implementações são:
///  * `IcomNetworkRadio` (`icom_link.dart`) — IC-705 via Wi-Fi (protocolo de rede Icom, como o RS-MS1A);
///  * `SimRadio` (`engine/sim_radio.dart`) — simulador para desenvolvimento e testes sem rádio.
///
/// Para suportar outro rádio/transporte (USB-OTG, Bluetooth SPP + áudio USB, Yaesu/Kenwood...),
/// crie uma nova implementação desta interface — veja `docs/ARQUITETURA.md`.
library;

import 'dart:async';
import 'dart:typed_data';

import 'civ.dart';

/// Estado da conexão.
enum LinkStatus { disconnected, connecting, connected, error }

abstract class RadioLink {
  /// Taxa de amostragem do áudio trocado com o rádio (PCM 16 bit mono).
  static const int audioRate = 48000;

  LinkStatus get status;

  /// Texto legível do estado (ex.: erro de autenticação).
  String get statusText;

  /// Espelho do estado do rádio (frequência, modo, potência, medidores...).
  RadioState get state;

  /// Fluxo de áudio recebido do rádio: PCM s16le, mono, 48 kHz. **Esta é a fonte da decodificação**,
  /// por isso o caminho de áudio foi projetado para o menor atraso possível (veja `docs/AUDIO.md`).
  Stream<Int16List> get rxAudio;

  /// Notifica qualquer mudança de estado (conexão, frequência, modo, medidores...).
  Stream<void> get changes;

  Future<void> connect();
  Future<void> disconnect();

  /// Liga/desliga o PTT (via CI-V).
  void setPtt(bool on);

  /// Define a frequência do VFO ativo (Hz).
  void setFrequency(int hz);

  /// Seleciona USB com DATA ligado (USB-D): ajuste padrão para modos digitais.
  void setUsbData();

  /// Define o modo CI-V (0 LSB, 1 USB...) e o filtro (1..3).
  void setMode(int mode, {int filter = 1});

  /// Liga/desliga o modo DATA.
  void setDataMode(bool on, {int filter = 1});

  /// Define a potência de RF (0..255).
  void setRfPower(int raw);

  /// Pré-amplificador: 0 desligado, 1 P.AMP1, 2 P.AMP2.
  void setPreamp(int value);

  /// Atenuador: 0 desligado, 20 ligado (dB).
  void setAtt(int db);

  /// Pede ao rádio todos os parâmetros sincronizáveis (frequência, modo, DATA, potência, pré, ATT).
  /// As respostas chegam de forma assíncrona e atualizam [state] (notificando em [changes]).
  void requestState();

  /// Envia áudio de TX: PCM s16le mono 48 kHz. O chamador respeita o ritmo de tempo real.
  void sendTxAudio(Int16List pcm);

  /// Envia um quadro CI-V cru.
  void sendCiv(Uint8List frame);

  /// Latência de ida e volta (ms), se conhecida.
  int? get pingMs;

  /// Pacotes de áudio/serial perdidos desde a conexão.
  int get lostPackets;
}
