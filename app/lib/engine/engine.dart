import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../core/ftx_native.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../radio/icom_link.dart';
import '../radio/radio_link.dart';
import 'qso.dart';
import 'qso_log.dart';
import 'sim_radio.dart';
import 'waterfall.dart';

/// Motor do aplicativo: relógio de slots, áudio de RX, waterfall, decodificação, TX e QSO.
class Engine extends ChangeNotifier {
  Engine({required this.settings, required this.codec, DateTime Function()? clock, QsoLog? log})
      : _clockFn = clock ?? DateTime.now,
        qsoLog = log ?? QsoLog() {
    qso = QsoManager(myCall: settings.callsign, myGrid: settings.grid, cqText: settings.customCq);
    settings.addListener(_onSettings);
  }

  final Settings settings;
  final FtxCodec codec;
  final QsoLog qsoLog;
  final DateTime Function() _clockFn;
  late QsoManager qso;

  // ------------------------------------------------------------------ estado público
  RadioLink? radio;
  final List<Decode> decodes = [];
  final WaterfallBuffer waterfall = WaterfallBuffer();
  final ValueNotifier<int> wfTick = ValueNotifier(0); // novo quadro de waterfall
  final ValueNotifier<int> clockTick = ValueNotifier(0); // relógio/slot (10 Hz)
  ui.Image? wfImage;

  bool monitoring = false;
  bool txEnabled = false;
  bool transmitting = false;
  bool tuning = false;
  int txParity = 0; // 0 = 1º slot (par), 1 = 2º slot (ímpar)
  String? txMessageShown;
  String? lastError;
  double rxLevelDb = -90; // nível do áudio de RX (dBFS)
  double lastDecodeSeconds = 0;
  int decodesLastSlot = 0;
  bool decoding = false;
  String statusLine = '';
  final List<String> txLog = [];
  Decode? selected;

  FtxProtocol get protocol => settings.protocol;

  // ------------------------------------------------------------------ relógio
  DateTime now() => _clockFn().toUtc().add(Duration(milliseconds: settings.clockOffsetMs));

  int slotIndexAt(DateTime t) => (t.millisecondsSinceEpoch / (protocol.slotSeconds * 1000)).floor();
  DateTime slotStartOf(int idx) =>
      DateTime.fromMillisecondsSinceEpoch((idx * protocol.slotSeconds * 1000).round(), isUtc: true);
  double secondsIntoSlot(DateTime t) =>
      (t.millisecondsSinceEpoch - slotStartOf(slotIndexAt(t)).millisecondsSinceEpoch) / 1000.0;
  int get currentSlotParity => slotIndexAt(now()) % 2;

  // ------------------------------------------------------------------ internos
  Timer? _timer;
  StreamSubscription<Int16List>? _audioSub;
  StreamSubscription<void>? _radioSub;
  Decimator? _dec;
  int _slotIdx = -1;
  late Float32List _slotBuf;
  int _slotWrite = 0;
  bool _decodedThisSlot = false;
  bool _slotHadTx = false;
  final Float32List _specRing = Float32List(kWfNfft);
  int _specFill = 0;
  int _specSince = 0;
  DateTime _lastImageAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _imageBusy = false;
  // TX
  Timer? _txTimer;
  Int16List? _txPcm;
  int _txSent = 0;
  DateTime? _txSlotStart;
  int _txCount = 0;
  int _lastTxSlot = -1;
  Timer? _tuneTimer;

  void _onSettings() {
    qso.myCall = settings.callsign;
    qso.myGrid = settings.grid;
    qso.cqText = settings.customCq;
  }

  // ------------------------------------------------------------------ conexão
  Future<void> start() async {
    _resetSlotBuffer();
    _timer ??= Timer.periodic(const Duration(milliseconds: 20), (_) => _tick());
    await connectRadio();
  }

  void _resetSlotBuffer() {
    _slotBuf = Float32List((protocol.slotSeconds * 12000).round() + 12000);
    _slotWrite = 0;
  }

  Future<void> connectRadio() async {
    await _disposeRadio();
    lastError = null;
    final RadioLink r;
    if (settings.radioKind == RadioKind.simulator) {
      r = SimRadio(codec: codec, protocol: () => protocol, myCall: () => settings.callsign, clock: now);
    } else {
      r = IcomNetworkRadio(ip: settings.radioIp, username: settings.radioUser, password: settings.radioPass);
    }
    radio = r;
    _dec = codec.newDecimator();
    _audioSub = r.rxAudio.listen(_onRxAudio);
    _radioSub = r.changes.listen((_) {
      if (r.status == LinkStatus.connected && !_radioInit) {
        _radioInit = true;
        if (settings.setRadioOnConnect && settings.radioKind == RadioKind.icomWifi) {
          Future<void>.delayed(const Duration(milliseconds: 300), () {
            if (radio == r) _applyRadioConfig();
          });
        }
      }
      notifyListeners();
    });
    _radioInit = false;
    monitoring = true;
    notifyListeners();
    await r.connect();
    notifyListeners();
  }

  bool _radioInit = false;

  void _applyRadioConfig() {
    final r = radio;
    if (r == null || r.status != LinkStatus.connected) return;
    r.setUsbData();
    r.setFrequency(dialFrequency);
  }

  int get dialFrequency {
    final b = kBands[settings.bandIndex.clamp(0, kBands.length - 1)];
    return protocol == FtxProtocol.ft4 ? b.ft4 : b.ft8;
  }

  Future<void> _disposeRadio() async {
    stopTx();
    await _audioSub?.cancel();
    await _radioSub?.cancel();
    _audioSub = _radioSub = null;
    _dec?.dispose();
    _dec = null;
    final r = radio;
    radio = null;
    await r?.disconnect();
  }

  Future<void> disconnectRadio() async {
    await _disposeRadio();
    monitoring = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _txTimer?.cancel();
    _tuneTimer?.cancel();
    settings.removeListener(_onSettings);
    _disposeRadio();
    super.dispose();
  }

  // ------------------------------------------------------------------ controles
  void setBand(int index) {
    settings.bandIndex = index;
    settings.save();
    radio?.setFrequency(dialFrequency);
    notifyListeners();
  }

  void setProtocol(FtxProtocol p) {
    if (p == settings.protocol) return;
    stopTx();
    settings.protocol = p;
    settings.save();
    _resetSlotBuffer();
    _slotIdx = -1;
    radio?.setFrequency(dialFrequency);
    notifyListeners();
  }

  void setRxFreq(int hz) {
    settings.rxFreq = hz.clamp(100, 3100);
    if (!settings.holdTxFreq) settings.txFreq = settings.rxFreq;
    settings.save();
    notifyListeners();
    _reencodeIfTransmitting();
  }

  void setTxFreq(int hz, {bool persist = true}) {
    settings.txFreq = hz.clamp(100, 3100);
    if (persist) settings.save();
    notifyListeners();
  }

  void _reencodeIfTransmitting() {}

  /// Notifica a interface apÃ³s alteraÃ§Ãµes diretas em [qso].
  void refresh() => notifyListeners();

  void setTxEnabled(bool on) {
    if (on && settings.callsign.isEmpty) {
      lastError = 'Configure seu indicativo antes de transmitir.';
      notifyListeners();
      return;
    }
    if (on && (radio == null || radio!.status != LinkStatus.connected)) {
      lastError = 'Rádio não conectado.';
      notifyListeners();
      return;
    }
    txEnabled = on;
    lastError = null;
    if (on) {
      _txCount = 0;
      if (qso.txParity != null) txParity = qso.txParity!;
    } else {
      stopTx();
    }
    notifyListeners();
  }

  void haltTx() {
    txEnabled = false;
    stopTx();
    notifyListeners();
  }

  void setTxParity(int p) {
    txParity = p;
    notifyListeners();
  }

  void selectTxMessage(int i) {
    qso.txIndex = i;
    notifyListeners();
  }

  /// Clique numa decodificação: seleciona a estação e prepara o QSO.
  void selectDecode(Decode d, {bool startQso = false}) {
    selected = d;
    if (startQso) {
      final parity = slotIndexAt(d.slotStart) % 2;
      qso.startWith(d, slotParity: parity);
      txParity = qso.txParity ?? txParity;
      setRxFreq(d.freq.round());
      if (!settings.holdTxFreq) settings.txFreq = d.freq.round();
      settings.save();
    }
    notifyListeners();
  }

  void callCq() {
    qso.clear();
    qso.txIndex = 6;
    notifyListeners();
  }

  void clearDecodes() {
    decodes.clear();
    notifyListeners();
  }

  // ------------------------------------------------------------------ áudio de RX
  void _onRxAudio(Int16List pcm48) {
    final dec = _dec;
    if (dec == null) return;
    final f = dec.process(pcm48);
    if (f.isEmpty) return;

    // nível
    var sum = 0.0;
    for (final v in f) {
      sum += v * v;
    }
    final rms = sqrt(sum / f.length);
    final db = rms > 1e-6 ? 20 * log(rms) / ln10 : -120.0;
    rxLevelDb = rxLevelDb * 0.7 + db * 0.3;

    if (transmitting || tuning) return; // não grava/decodifica durante a TX

    // buffer do slot atual
    final room = _slotBuf.length - _slotWrite;
    final n = min(room, f.length);
    if (n > 0) {
      _slotBuf.setRange(_slotWrite, _slotWrite + n, f);
      _slotWrite += n;
    }

    // espectro para waterfall
    var off = 0;
    while (off < f.length) {
      final take = min(f.length - off, kWfNfft - _specFill);
      _specRing.setRange(_specFill, _specFill + take, f, off);
      _specFill += take;
      off += take;
      _specSince += take;
      if (_specFill == kWfNfft) {
        // desliza a janela (mantém 3/4 do conteúdo)
        if (_specSince >= 1800) {
          _computeSpectrumRow();
          _specSince = 0;
        }
        _specRing.setRange(0, kWfNfft - 1024, _specRing, 1024);
        _specFill = kWfNfft - 1024;
      }
    }
  }

  void _computeSpectrumRow() {
    final db = codec.spectrum(_specRing, kWfNfft);
    if (db.length < kWfBins) return;
    waterfall.pushRow(db, now().millisecondsSinceEpoch,
        auto: settings.wfAuto, gain: settings.wfGain, zero: settings.wfZero);
    wfTick.value++;
    final t = DateTime.now();
    if (!_imageBusy && t.difference(_lastImageAt).inMilliseconds > 90) {
      _imageBusy = true;
      _lastImageAt = t;
      waterfall.toImage().then((img) {
        final old = wfImage;
        wfImage = img;
        old?.dispose();
        _imageBusy = false;
        wfTick.value++;
      });
    }
  }

  // ------------------------------------------------------------------ ciclo de slots
  void _tick() {
    final t = now();
    final idx = slotIndexAt(t);
    if (idx != _slotIdx) _onNewSlot(idx);
    final sec = secondsIntoSlot(t);

    // decodificação ao final do slot
    final decodeAt = protocol.slotSeconds - (protocol == FtxProtocol.ft8 ? 1.0 : 1.1);
    if (!_decodedThisSlot && sec >= decodeAt && monitoring && _slotIdx >= 0) {
      _decodedThisSlot = true;
      if (!_slotHadTx) _runDecode(_slotIdx);
    }

    // início de TX
    if (txEnabled && !transmitting && !tuning && idx % 2 == txParity && idx != _lastTxSlot && sec < 2.0) {
      _startTx(idx, sec);
    }

    if (clockTick.value % 5 == 0) {
      // atualiza a interface ~10 Hz
    }
    clockTick.value++;
  }

  void _onNewSlot(int idx) {
    _slotIdx = idx;
    _slotWrite = 0;
    _decodedThisSlot = false;
    _slotHadTx = transmitting || tuning;
  }

  Future<void> _runDecode(int slotIdx) async {
    final samples = Float32List.fromList(_slotBuf.sublist(0, _slotWrite));
    if (samples.length < 12000 * 3) return;
    final slotStart = slotStartOf(slotIdx);
    final sw = Stopwatch()..start();
    decoding = true;
    notifyListeners();
    List<RawDecode> raw;
    try {
      raw = await codec.decodeAsync(samples, protocol);
    } catch (e) {
      lastError = 'Falha na decodificação: $e';
      decoding = false;
      notifyListeners();
      return;
    }
    lastDecodeSeconds = sw.elapsedMilliseconds / 1000.0;
    decoding = false;
    final parity = slotIdx % 2;
    final fresh = <Decode>[];
    for (final r in raw) {
      fresh.add(Decode(
        slotStart: slotStart,
        snr: r.snrDb,
        dt: r.dtSec,
        freq: r.freqHz,
        message: r.text,
        myCall: settings.callsign,
        myGrid: settings.grid,
      ));
    }
    fresh.sort((a, b) => a.freq.compareTo(b.freq));
    decodes.addAll(fresh);
    if (decodes.length > 800) decodes.removeRange(0, decodes.length - 800);
    decodesLastSlot = fresh.length;

    // auto-sequência
    if (settings.autoSeq) {
      for (final d in fresh) {
        if (!d.toMe) continue;
        final ev = qso.onDecode(d, slotParity: parity);
        if (qso.txParity != null) txParity = qso.txParity!;
        if (settings.autoSeq && !settings.holdTxFreq && qso.dxCall.isNotEmpty) {
          // transmite na mesma frequência do correspondente
          settings.txFreq = d.freq.round();
        }
        if (ev == QsoEvent.complete) {
          _logCurrentQso();
        }
        break;
      }
    }
    notifyListeners();
  }

  void _logCurrentQso() {
    if (qso.dxCall.isEmpty) return;
    final r = radio;
    final freq = r?.state.freqHz ?? dialFrequency;
    qsoLog.add(QsoRecord(
      call: qso.dxCall,
      grid: qso.dxGrid,
      time: now(),
      freqHz: freq,
      mode: protocol.label,
      rstSent: qso.rptSent,
      rstRcvd: qso.rptRcvd,
      myCall: settings.callsign,
      myGrid: settings.grid,
    ));
    txLog.add('QSO registrado com ${qso.dxCall}');
  }

  /// Registro manual do QSO atual (botão "Registrar").
  void logQsoNow() {
    _logCurrentQso();
    notifyListeners();
  }

  // ------------------------------------------------------------------ transmissão
  void _startTx(int slotIdx, double secIntoSlot) {
    final r = radio;
    if (r == null || r.status != LinkStatus.connected) {
      txEnabled = false;
      lastError = 'Rádio desconectado – TX desativado.';
      notifyListeners();
      return;
    }
    final text = qso.currentMessage;
    final tones = codec.encode(text, protocol);
    if (tones == null) {
      txEnabled = false;
      lastError = 'Mensagem inválida: "$text"';
      notifyListeners();
      return;
    }
    final wave = codec.synth(tones, protocol, settings.txFreq.toDouble(), RadioLink.audioRate);
    final lead = (0.5 * RadioLink.audioRate).round();
    final pcm = Int16List(lead + wave.length + RadioLink.audioRate ~/ 10);
    final amp = (settings.txLevel.clamp(0.0, 1.0)) * 32000;
    for (var i = 0; i < wave.length; i++) {
      pcm[lead + i] = (wave[i] * amp).round();
    }
    _txPcm = pcm;
    _txSlotStart = slotStartOf(slotIdx);
    _txSent = 0;
    _lastTxSlot = slotIdx;
    transmitting = true;
    txMessageShown = text;
    _txCount++;
    txLog.add('${_hhmmss(now())}  TX ${settings.txFreq} Hz  $text');
    if (r is SimRadio) r.heardTransmission(text, settings.txFreq.toDouble());
    r.setPtt(true);
    _txTimer?.cancel();
    _txTimer = Timer.periodic(const Duration(milliseconds: 20), (_) => _txStep());
    notifyListeners();
  }

  void _txStep() {
    final r = radio;
    final pcm = _txPcm;
    if (r == null || pcm == null || r.status != LinkStatus.connected) {
      stopTx();
      return;
    }
    final elapsed = now().difference(_txSlotStart!).inMicroseconds / 1e6;
    final target = ((elapsed + 0.12) * RadioLink.audioRate).floor().clamp(0, pcm.length);
    if (target > _txSent) {
      r.sendTxAudio(Int16List.sublistView(pcm, _txSent, target));
      _txSent = target;
    }
    if (_txSent >= pcm.length && elapsed * RadioLink.audioRate >= pcm.length) {
      _finishTx();
    }
  }

  void _finishTx() {
    stopTx();
    // Após enviar 73, encerra; em QSO normal mantém repetindo a mensagem atual.
    if (qso.txIndex == 5 && qso.dxCall.isNotEmpty) {
      if (!qso.completed) _logCurrentQso();
      txEnabled = false;
      qso.clear();
    } else if (qso.dxCall.isNotEmpty && _txCount >= 12) {
      txEnabled = false;
      lastError = 'Sem resposta de ${qso.dxCall}: TX desativado.';
    }
    notifyListeners();
  }

  void stopTx() {
    _txTimer?.cancel();
    _txTimer = null;
    _tuneTimer?.cancel();
    _tuneTimer = null;
    final wasKeyed = transmitting || tuning;
    transmitting = false;
    tuning = false;
    _txPcm = null;
    if (wasKeyed) radio?.setPtt(false);
    notifyListeners();
  }

  /// "Tune": emite uma portadora de áudio contínua (para ajuste de antena/potência) por até 10 s.
  void tune(bool on) {
    final r = radio;
    if (!on) {
      stopTx();
      return;
    }
    if (r == null || r.status != LinkStatus.connected || transmitting) return;
    tuning = true;
    r.setPtt(true);
    var phase = 0.0;
    final w = 2 * pi * settings.txFreq / RadioLink.audioRate;
    final amp = settings.txLevel.clamp(0.0, 1.0) * 32000;
    var started = now();
    _tuneTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final el = now().difference(started).inMilliseconds;
      if (el > 10000) {
        stopTx();
        return;
      }
      final chunk = Int16List(960);
      for (var i = 0; i < chunk.length; i++) {
        chunk[i] = (sin(phase) * amp).round();
        phase += w;
      }
      r.sendTxAudio(chunk);
    });
    notifyListeners();
  }

  static String _hhmmss(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}
