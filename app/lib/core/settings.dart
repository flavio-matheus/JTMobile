import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ftx_native.dart';

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
  FtxProtocol protocol = FtxProtocol.ft8;
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

  void _read() {
    final p = _p;
    if (p == null) return;
    callsign = p.getString('callsign') ?? callsign;
    grid = p.getString('grid') ?? grid;
    radioIp = p.getString('radioIp') ?? radioIp;
    radioUser = p.getString('radioUser') ?? radioUser;
    radioPass = p.getString('radioPass') ?? radioPass;
    radioKind = RadioKind.values[(p.getInt('radioKind') ?? radioKind.index).clamp(0, RadioKind.values.length - 1)];
    protocol = (p.getInt('protocol') ?? 0) == 1 ? FtxProtocol.ft4 : FtxProtocol.ft8;
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
    await p.setInt('protocol', protocol.id);
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
