/// Configurações persistentes do app (SharedPreferences): estação, rádio, modo/banda, TX, waterfall,
/// sincronização com o rádio e logbook. Cada campo tem valor padrão seguro; [Settings.save] grava tudo
/// e notifica os ouvintes. Em testes use [Settings.memory].
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/radio_sync.dart';
import 'ftx_native.dart';
import 'modes.dart';

enum RadioKind { icomWifi, simulator }

/// Configurações persistentes do app.
class Settings extends ChangeNotifier {
  Settings._(this._p);
  final SharedPreferences? _p;

  static Future<Settings> load() async {
    SharedPreferences? p;
    try {
      p = await SharedPreferences.getInstance();
    } catch (_) {}
    final s = Settings._(p);
    s._read();
    return s;
  }

  /// Para testes (sem persistência).
  factory Settings.memory() => Settings._(null);

  String callsign = '';
  String grid = '';
  String radioIp = '192.168.200.1';
  String radioUser = '';
  String radioPass = '';
  RadioKind radioKind = RadioKind.simulator;
  /// Id do modo digital ativo (veja [kModes]).
  String modeId = 'FT8';
  int bandIndex = 5; // 20m
  int rxFreq = 1500;
  int txFreq = 1500;
  double txLevel = 0.5; // 0..1 (amplitude do áudio enviado ao rádio)
  double wfGain = 0.5; // 0..1
  double wfZero = 0.5; // 0..1
  bool wfAuto = true;
  bool autoSeq = true;
  bool holdTxFreq = false;
  bool callFirstOnReply = true;
  bool setRadioOnConnect = true;
  int clockOffsetMs = 0;
  int rxLatencyMs = 0;
  String customCq = 'CQ';

  /// Quem prevalece ao conectar: rádio (padrão) ou app. Veja engine/radio_sync.dart.
  SyncPolicy syncPolicy = SyncPolicy.radioFirst;

  /// Corrige automaticamente o rádio para USB-D ao conectar (e avisa se for alterado depois).
  bool autoFixMode = true;

  /// Grava o QSO no log sem abrir o diálogo de confirmação.
  bool autoLog = false;

  /// Buffer de áudio de TX pedido ao rádio (ms): menor = menos atraso, porém mais sensível a jitter.
  int txBufferMs = 150;

  /// Avanço do envio do áudio de TX (ms) para compensar o atraso do enlace; ajuste fino por DT.
  int txAdvanceMs = 0;

  /// Som nos alertas (início de TX, resposta de estação, QSO completo).
  bool alertSound = true;

  /// Vibração nos alertas.
  bool alertVibrate = true;

  /// Faixa de aviso (pop-up) no topo da tela. Desligue para operar sem os avisos visuais em faixa.
  bool alertBanner = true;

  /// Borda da tela que pisca a cada alerta.
  bool alertFlash = true;

  /// **Auto TX**: tocar em "responder" (↩) já arma a transmissão (como o duplo clique do WSJT-X/JTDX).
  /// Desligado, o ↩ só seleciona a estação e o TX é armado manualmente em "Ativar TX".
  /// (Chave persistida mantida como `replyEnablesTx` por compatibilidade.)
  bool replyEnablesTx = true;

  /// Número máximo de transmissões repetidas da mesma etapa sem resposta antes de desarmar o TX.
  int txMaxAttempts = 12;

  /// Reproduz o áudio recebido do rádio no alto-falante do celular (para ouvir o "assobio" dos modos digitais).
  bool monitorSpeaker = false;

  /// Volume do monitor de áudio (0..1), aplicado sobre o volume de mídia do celular.
  double monitorVolume = 0.8;

  /// O tutorial de boas-vindas já foi exibido.
  bool tutorialSeen = false;

  /// Modo digital ativo.
  ModeSpec get mode => modeById(modeId);

  /// Codec FT8/FT4 do modo ativo (FT8 como reserva).
  FtxProtocol get protocol => mode.ftx ?? FtxProtocol.ft8;

  void _read() {
    final p = _p;
    if (p == null) return;
    callsign = p.getString('callsign') ?? callsign;
    grid = p.getString('grid') ?? grid;
    radioIp = p.getString('radioIp') ?? radioIp;
    radioUser = p.getString('radioUser') ?? radioUser;
    radioPass = p.getString('radioPass') ?? radioPass;
    radioKind = RadioKind.values[(p.getInt('radioKind') ?? radioKind.index).clamp(0, RadioKind.values.length - 1)];
    modeId = p.getString('modeId') ?? modeId;
    syncPolicy = SyncPolicy.values[(p.getInt('syncPolicy') ?? 0).clamp(0, SyncPolicy.values.length - 1)];
    autoFixMode = p.getBool('autoFixMode') ?? autoFixMode;
    autoLog = p.getBool('autoLog') ?? autoLog;
    alertSound = p.getBool('alertSound') ?? alertSound;
    alertVibrate = p.getBool('alertVibrate') ?? alertVibrate;
    replyEnablesTx = p.getBool('replyEnablesTx') ?? replyEnablesTx;
    alertBanner = p.getBool('alertBanner') ?? alertBanner;
    alertFlash = p.getBool('alertFlash') ?? alertFlash;
    txMaxAttempts = p.getInt('txMaxAttempts') ?? txMaxAttempts;
    monitorSpeaker = p.getBool('monitorSpeaker') ?? monitorSpeaker;
    monitorVolume = p.getDouble('monitorVolume') ?? monitorVolume;
    tutorialSeen = p.getBool('tutorialSeen') ?? tutorialSeen;
    txBufferMs = p.getInt('txBufferMs') ?? txBufferMs;
    txAdvanceMs = p.getInt('txAdvanceMs') ?? txAdvanceMs;
    bandIndex = p.getInt('bandIndex') ?? bandIndex;
    rxFreq = p.getInt('rxFreq') ?? rxFreq;
    txFreq = p.getInt('txFreq') ?? txFreq;
    txLevel = p.getDouble('txLevel') ?? txLevel;
    wfGain = p.getDouble('wfGain') ?? wfGain;
    wfZero = p.getDouble('wfZero') ?? wfZero;
    wfAuto = p.getBool('wfAuto') ?? wfAuto;
    autoSeq = p.getBool('autoSeq') ?? autoSeq;
    holdTxFreq = p.getBool('holdTxFreq') ?? holdTxFreq;
    setRadioOnConnect = p.getBool('setRadioOnConnect') ?? setRadioOnConnect;
    clockOffsetMs = p.getInt('clockOffsetMs') ?? clockOffsetMs;
    rxLatencyMs = p.getInt('rxLatencyMs') ?? rxLatencyMs;
    customCq = p.getString('customCq') ?? customCq;
  }

  Future<void> save() async {
    final p = _p;
    notifyListeners();
    if (p == null) return;
    await p.setString('callsign', callsign);
    await p.setString('grid', grid);
    await p.setString('radioIp', radioIp);
    await p.setString('radioUser', radioUser);
    await p.setString('radioPass', radioPass);
    await p.setInt('radioKind', radioKind.index);
    await p.setString('modeId', modeId);
    await p.setInt('syncPolicy', syncPolicy.index);
    await p.setBool('autoFixMode', autoFixMode);
    await p.setBool('autoLog', autoLog);
    await p.setBool('alertSound', alertSound);
    await p.setBool('alertVibrate', alertVibrate);
    await p.setBool('replyEnablesTx', replyEnablesTx);
    await p.setBool('alertBanner', alertBanner);
    await p.setBool('alertFlash', alertFlash);
    await p.setInt('txMaxAttempts', txMaxAttempts);
    await p.setBool('monitorSpeaker', monitorSpeaker);
    await p.setDouble('monitorVolume', monitorVolume);
    await p.setBool('tutorialSeen', tutorialSeen);
    await p.setInt('txBufferMs', txBufferMs);
    await p.setInt('txAdvanceMs', txAdvanceMs);
    await p.setInt('bandIndex', bandIndex);
    await p.setInt('rxFreq', rxFreq);
    await p.setInt('txFreq', txFreq);
    await p.setDouble('txLevel', txLevel);
    await p.setDouble('wfGain', wfGain);
    await p.setDouble('wfZero', wfZero);
    await p.setBool('wfAuto', wfAuto);
    await p.setBool('autoSeq', autoSeq);
    await p.setBool('holdTxFreq', holdTxFreq);
    await p.setBool('setRadioOnConnect', setRadioOnConnect);
    await p.setInt('clockOffsetMs', clockOffsetMs);
    await p.setInt('rxLatencyMs', rxLatencyMs);
    await p.setString('customCq', customCq);
  }
}
