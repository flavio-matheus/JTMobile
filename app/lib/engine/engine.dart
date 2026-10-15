/// Motor do JTMobile: orquestra rádio, áudio, decodificação, transmissão, QSO e logbook.
///
/// ## Visão geral do fluxo
/// ```
///  Rádio (UDP) ──áudio 48 kHz──▶ AudioTimeline ──▶ decimador 12 kHz ──▶ buffer do slot ──▶ decodificador
///        ▲                         (hora de captura)        │                    │
///        │ CI-V / PTT / áudio TX                            └──▶ FFT ──▶ waterfall
///  RadioSync ◀──────▶ estado do app (banda, modo, frequência, potência)
/// ```
///  * **Áudio de RX → decodificação.** Cada pacote recebe uma hora de captura estimada por
///    [AudioTimeline] (imune a jitter de rede). As amostras são posicionadas no buffer do período
///    (*slot*) por essa hora, e a decodificação dispara quando o **áudio** atinge o instante
///    configurado do modo (`ModeSpec.decodeAtSeconds`) — não quando o relógio de parede diz.
///  * **Sincronização app↔rádio** ([RadioSync]): frequência, modo, DATA, potência etc. fluem nos
///    dois sentidos; veja `radio_sync.dart`.
///  * **TX**: no início do período de transmissão o texto é codificado, o sinal GFSK sintetizado a
///    48 kHz e enviado ao rádio em tempo real, com PTT via CI-V.
///  * **QSO**: [QsoManager] implementa Tx1..Tx6 e a auto-sequência; ao concluir, o QSO vai ao
///    logbook (com confirmação opcional).
///
/// A interface observa este objeto (`ChangeNotifier`) e dois `ValueNotifier` de alta frequência:
/// [wfTick] (novo quadro de waterfall) e [clockTick] (relógio, 50 Hz).
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../core/ftx_native.dart';
import '../core/models.dart';
import '../core/modes.dart';
import '../core/settings.dart';
import '../logbook/qso_log.dart';
import '../logbook/qso_record.dart';
import '../radio/icom_link.dart';
import '../radio/radio_link.dart';
import 'alerts.dart';
import 'audio_timeline.dart';
import 'qso.dart';
import 'radio_sync.dart';
import 'sim_radio.dart';
import 'waterfall.dart';

class Engine extends ChangeNotifier {
  Engine({
    required this.settings,
    required this.codec,
    DateTime Function()? clock,
    QsoLog? log,
    AlertCenter? alerts,
  })  : _clockFn = clock ?? DateTime.now,
        qsoLog = log ?? QsoLog(),
        alerts = alerts ?? AlertCenter() {
    qso = QsoManager(myCall: settings.callsign, myGrid: settings.grid, cqText: settings.customCq);
    settings.addListener(_onSettings);
    _onSettings();
  }

  /// Alertas visuais/sonoros ao operador (início de TX, resposta de estação, QSO completo).
  final AlertCenter alerts;

  /// Configurações persistentes.
  final Settings settings;

  /// Codec nativo (decodificação/codificação/FFT/decimação).
  final FtxCodec codec;

  /// Logbook persistente.
  final QsoLog qsoLog;
  final DateTime Function() _clockFn;

  /// Sequenciador de QSO (mensagens Tx1..Tx6).
  late QsoManager qso;

  // ------------------------------------------------------------------ estado público (UI)

  /// Enlace atual com o rádio (ou `null` se desconectado).
  RadioLink? radio;

  /// Mensagens decodificadas (mais antigas primeiro; limitado a 800).
  final List<Decode> decodes = [];

  /// Dados da waterfall.
  final WaterfallBuffer waterfall = WaterfallBuffer();

  /// Incrementa a cada novo quadro de waterfall.
  final ValueNotifier<int> wfTick = ValueNotifier(0);

  /// Incrementa a cada tick do relógio (50 Hz) — para barras de progresso e relógio.
  final ValueNotifier<int> clockTick = ValueNotifier(0);

  /// Imagem atual da waterfall.
  ui.Image? wfImage;

  /// QSO concluído aguardando confirmação do usuário no diálogo "Registrar QSO" (`null` = nenhum).
  final ValueNotifier<QsoRecord?> pendingLog = ValueNotifier(null);

  bool monitoring = false;
  bool txEnabled = false;
  bool transmitting = false;
  bool tuning = false;

  /// Período em que o app transmite: 0 = 1º (par), 1 = 2º (ímpar).
  int txParity = 0;

  /// Mensagem em transmissão (para exibição).
  String? txMessageShown;

  /// Último erro/aviso para o usuário.
  String? lastError;

  /// Nível do áudio de RX em dBFS (suavizado).
  double rxLevelDb = -90;

  /// Duração da última decodificação (s) e nº de mensagens do último slot.
  double lastDecodeSeconds = 0;
  int decodesLastSlot = 0;
  bool decoding = false;

  /// Linhas do histórico de transmissões.
  final List<String> txLog = [];

  /// Decodificação selecionada na lista.
  Decode? selected;

  /// Jitter médio de chegada do áudio (ms), medido pela [AudioTimeline].
  double audioJitterMs = 0;

  /// Quantas vezes foi inserido silêncio por perda de áudio (desde a conexão).
  int audioGapsFilled = 0;

  /// Modo digital ativo.
  ModeSpec get mode => settings.mode;

  /// Codec FT8/FT4 do modo ativo.
  FtxProtocol get protocol => settings.protocol;

  // ------------------------------------------------------------------ relógio

  /// Hora UTC corrigida pela compensação do usuário (`clockOffsetMs`).
  DateTime now() => _clockFn().toUtc().add(Duration(milliseconds: settings.clockOffsetMs));

  /// Índice absoluto do período (slot) que contém [t].
  int slotIndexAt(DateTime t) => (t.millisecondsSinceEpoch / (mode.slotSeconds * 1000)).floor();

  /// Instante de início do slot [idx].
  DateTime slotStartOf(int idx) =>
      DateTime.fromMillisecondsSinceEpoch((idx * mode.slotSeconds * 1000).round(), isUtc: true);

  /// Segundos decorridos no slot atual em [t].
  double secondsIntoSlot(DateTime t) =>
      (t.millisecondsSinceEpoch - slotStartOf(slotIndexAt(t)).millisecondsSinceEpoch) / 1000.0;

  /// Paridade do slot atual (0 = 1º/par, 1 = 2º/ímpar).
  int get currentSlotParity => slotIndexAt(now()) % 2;

  // ------------------------------------------------------------------ internos

  Timer? _timer;
  StreamSubscription<Int16List>? _audioSub;
  StreamSubscription<void>? _radioSub;
  Decimator? _dec;
  RadioSync? _sync;
  bool _radioInit = false;

  // áudio / slot
  final AudioTimeline _timeline = AudioTimeline();
  late Float32List _slotBuf;
  int _bufSlot = -1; // slot a que o buffer pertence
  int _slotWrite = 0; // amostras (12 kHz) válidas no buffer
  bool _decodedThisSlot = false;
  final Float32List _specRing = Float32List(kWfNfft);
  int _specFill = 0;
  int _specSince = 0;
  int _lastAudioMs = 0;
  DateTime _lastImageAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _imageBusy = false;
  final List<double> _dtSamples = [];

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
    alerts.soundEnabled = settings.alertSound;
    alerts.vibrateEnabled = settings.alertVibrate;
  }

  // ------------------------------------------------------------------ guia de operação

  /// Indicativo e instante do último QSO concluído (para o guia na tela).
  String? lastQsoCall;
  DateTime? lastQsoAt;

  /// Última mensagem recebida **dirigida a mim** (resposta de estação) e quando.
  String? lastReplyText;
  DateTime? lastReplyAt;

  /// Quantas vezes já transmitimos nesta chamada/QSO (reinicia ao habilitar o TX).
  int get txAttempts => _txCount;

  /// Segundos até o início do próximo período de TX configurado ([txParity]); 0 se estamos nele.
  double secondsUntilTxSlot() {
    final t = now();
    final idx = slotIndexAt(t);
    var target = idx;
    if (target % 2 != txParity) target++;
    final startMs = slotStartOf(target).millisecondsSinceEpoch;
    final d = (startMs - t.millisecondsSinceEpoch) / 1000.0;
    return d < 0 ? 0 : d;
  }

  // ================================================================== conexão com o rádio

  /// Inicia o motor (timers), carrega o logbook e conecta ao rádio configurado.
  Future<void> start() async {
    _resetSlotBuffer();
    _timer ??= Timer.periodic(const Duration(milliseconds: 20), (_) => _tick());
    await qsoLog.load();
    await connectRadio();
  }

  void _resetSlotBuffer() {
    _slotBuf = Float32List((mode.slotSeconds * 12000).round());
    _slotWrite = 0;
    _bufSlot = -1;
    _decodedThisSlot = false;
    _timeline.reset();
  }

  /// (Re)conecta ao rádio conforme as configurações.
  Future<void> connectRadio() async {
    await _disposeRadio();
    lastError = null;
    final RadioLink r;
    if (settings.radioKind == RadioKind.simulator) {
      r = SimRadio(codec: codec, protocol: () => protocol, myCall: () => settings.callsign, clock: now);
    } else {
      r = IcomNetworkRadio(
        ip: settings.radioIp,
        username: settings.radioUser,
        password: settings.radioPass,
        txBufferMs: settings.txBufferMs,
      );
    }
    radio = r;
    _timeline.reset();
    _dec = codec.newDecimator();
    _sync = RadioSync(link: r, onRadioChange: _onRadioChange);
    _audioSub = r.rxAudio.listen(_onRxAudio);
    _radioInit = false;
    _radioSub = r.changes.listen((_) {
      if (r.status == LinkStatus.connected && !_radioInit) {
        _radioInit = true;
        _initialSync(r);
      }
      _sync?.onLinkChanged();
      notifyListeners();
    });
    monitoring = true;
    notifyListeners();
    await r.connect();
    notifyListeners();
  }

  /// Primeira sincronização depois de conectar: lê o rádio e aplica a política escolhida.
  Future<void> _initialSync(RadioLink r) async {
    r.requestState();
    // espera as respostas básicas (até 3 s)
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (radio != r) return;
      if (r.state.freqHz != null && r.state.mode != null) break;
    }
    final sync = _sync;
    if (sync == null || radio != r) return;
    final standard = dialFrequency;
    if (settings.syncPolicy == SyncPolicy.radioFirst) {
      sync.adoptAll(); // o app adota frequência/banda/potência do rádio
    } else if (r.state.freqHz != null && standard != null) {
      sync.pushFrequency(standard);
    }
    if (settings.autoFixMode && r.state.mode != null && !r.state.isUsbData) {
      sync.pushUsbData(); // FT8/FT4 exigem USB + DATA
    }
    notifyListeners();
  }

  /// Tratamento de mudanças feitas **no rádio** (botões, painel, transceive).
  void _onRadioChange(RadioChange c) {
    if (c.field == SyncField.frequency) {
      final bi = bandIndexOf(c.value);
      if (bi >= 0 && bi != settings.bandIndex) {
        settings.bandIndex = bi;
        settings.save();
      }
    }
    // modo/DATA/filtro/potência/pré/ATT são refletidos diretamente por [radio.state] na interface
    notifyListeners();
  }

  /// Frequência de dial padrão do modo/banda atuais (Hz) ou `null` se não houver padrão.
  int? get dialFrequency => kBands[settings.bandIndex.clamp(0, kBands.length - 1)].dialFor(mode.id);

  /// `true` quando o rádio está em USB-D (ajuste correto para FT8/FT4).
  bool get radioModeOk => radio?.state.isUsbData ?? true;

  /// `true` quando a frequência do rádio difere da frequência padrão do modo/banda.
  bool get radioOffStandardFrequency {
    final f = radio?.state.freqHz;
    final d = dialFrequency;
    return f != null && d != null && (f - d).abs() > 100;
  }

  /// Potência de RF do rádio em % (0..100), ou `null` se não lida.
  int? get rfPowerPercent {
    final p = radio?.state.rfPower;
    return p == null ? null : (p * 100 / 255).round();
  }

  Future<void> _disposeRadio() async {
    stopTx();
    await _audioSub?.cancel();
    await _radioSub?.cancel();
    _audioSub = _radioSub = null;
    _dec?.dispose();
    _dec = null;
    _sync = null;
    final r = radio;
    radio = null;
    await r?.disconnect();
  }

  /// Desconecta o rádio e para a monitoração.
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

  // ================================================================== controles (app -> rádio)

  /// Seleciona a banda [index] e leva o rádio à frequência padrão do modo atual.
  void setBand(int index) {
    settings.bandIndex = index;
    settings.save();
    final f = dialFrequency;
    if (f != null) _sync?.pushFrequency(f);
    notifyListeners();
  }

  /// Define a frequência de dial digitada pelo usuário (Hz).
  void setDialFrequency(int hz) {
    _sync?.pushFrequency(hz);
    final bi = bandIndexOf(hz);
    if (bi >= 0) settings.bandIndex = bi;
    settings.save();
    notifyListeners();
  }

  /// Leva o rádio à frequência padrão do modo/banda atuais e a USB-D.
  void goToStandardSetup() {
    final f = dialFrequency;
    if (f != null) _sync?.pushFrequency(f);
    _sync?.pushUsbData();
    notifyListeners();
  }

  /// Corrige o modo do rádio para USB-D.
  void fixRadioMode() {
    _sync?.pushUsbData();
    notifyListeners();
  }

  /// Altera a potência de RF do rádio (0..100 %).
  void setRfPowerPercent(int percent) {
    _sync?.pushRfPower((percent.clamp(0, 100) * 255 / 100).round());
    notifyListeners();
  }

  /// Pré-amplificador (0 desligado, 1, 2).
  void setPreamp(int v) {
    _sync?.pushPreamp(v);
    notifyListeners();
  }

  /// Atenuador (0 desligado, 20 dB).
  void setAtt(int db) {
    _sync?.pushAtt(db);
    notifyListeners();
  }

  /// Relê do rádio todos os parâmetros sincronizáveis.
  void syncNow() {
    radio?.requestState();
    _sync?.adoptAll();
    notifyListeners();
  }

  /// Seleciona o modo digital [m]. Modos ainda não implementados são recusados com aviso.
  void setMode(ModeSpec m) {
    if (!m.implemented) {
      lastError = '${m.label} ainda não está implementado (veja docs/MODOS.md).';
      notifyListeners();
      return;
    }
    if (m.id == settings.modeId) return;
    stopTx();
    settings.modeId = m.id;
    settings.save();
    _resetSlotBuffer();
    final f = dialFrequency;
    if (f != null) _sync?.pushFrequency(f);
    lastError = null;
    notifyListeners();
  }

  /// Compatibilidade: seleciona FT8/FT4 pelo codec.
  void setProtocol(FtxProtocol p) => setMode(kModes.firstWhere((m) => m.ftx == p));

  /// Define a frequência de RX (Hz de áudio); acompanha o TX salvo se "manter TX" estiver desligado.
  void setRxFreq(int hz) {
    settings.rxFreq = hz.clamp(100, 3100);
    if (!settings.holdTxFreq) settings.txFreq = settings.rxFreq;
    settings.save();
    notifyListeners();
  }

  /// Define a frequência de TX (Hz de áudio). [persist] = false durante arrastes (evita gravar a cada quadro).
  void setTxFreq(int hz, {bool persist = true}) {
    settings.txFreq = hz.clamp(100, 3100);
    if (persist) settings.save();
    notifyListeners();
  }

  /// Notifica a interface após alterações diretas em [qso].
  void refresh() => notifyListeners();

  /// Habilita/desabilita a transmissão automática no período configurado.
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

  /// HALT: interrompe imediatamente a transmissão e desabilita o TX.
  void haltTx() {
    txEnabled = false;
    stopTx();
    notifyListeners();
  }

  void setTxParity(int p) {
    txParity = p;
    notifyListeners();
  }

  /// Seleciona a mensagem Tx[i] (1..6) a transmitir.
  void selectTxMessage(int i) {
    qso.txIndex = i;
    notifyListeners();
  }

  /// Seleciona uma decodificação; com [startQso] prepara o QSO (responder à estação).
  void selectDecode(Decode d, {bool startQso = false}) {
    selected = d;
    if (startQso) {
      final parity = slotIndexAt(d.slotStart) % 2;
      qso.startWith(d, slotParity: parity);
      txParity = qso.txParity ?? txParity;
      setRxFreq(d.freq.round());
      if (!settings.holdTxFreq) settings.txFreq = d.freq.round();
      settings.save();
      // Como o duplo clique do WSJT-X/JTDX: responder já arma a transmissão.
      final dx = qso.dxCall;
      if (settings.replyEnablesTx) setTxEnabled(true);
      if (txEnabled) {
        alerts.show(AlertKind.info, 'Respondendo a $dx',
            'TX armado para o ${txParity == 0 ? '1º' : '2º'} período — começa em ${secondsUntilTxSlot().ceil()} s.');
      } else if (lastError == null) {
        alerts.show(AlertKind.info, '$dx selecionada', 'Toque em "Ativar TX" para chamar.');
      }
    }
    notifyListeners();
  }

  /// Volta ao modo "chamar CQ".
  void callCq() {
    qso.clear();
    qso.txIndex = 6;
    notifyListeners();
  }

  void clearDecodes() {
    decodes.clear();
    notifyListeners();
  }

  // ================================================================== áudio de RX

  /// Chegada de um pacote de áudio do rádio (PCM 16 bit, 48 kHz).
  ///
  /// Caminho crítico: mantido enxuto (decimação nativa + cópia para o buffer). A hora de captura
  /// vem da [AudioTimeline], não da hora de chegada do pacote.
  void _onRxAudio(Int16List pcm48) {
    final dec = _dec;
    if (dec == null || pcm48.isEmpty) return;
    final arrivalUs = now().microsecondsSinceEpoch;
    final timing = _timeline.onChunk(arrivalUs, pcm48.length);
    audioJitterMs = audioJitterMs * 0.95 + 0.05 * _estimateJitterMs(arrivalUs);

    final f = dec.process(pcm48);
    if (f.isEmpty) return;

    // nível (RMS)
    var sum = 0.0;
    for (final v in f) {
      sum += v * v;
    }
    final rms = sqrt(sum / f.length);
    final db = rms > 1e-6 ? 20 * log(rms) / ln10 : -120.0;
    rxLevelDb = rxLevelDb * 0.7 + db * 0.3;

    if (transmitting || tuning) return; // o rádio não envia RX útil durante a TX

    final startUs = timing.startUs - settings.rxLatencyMs * 1000;
    if (timing.padSamples > 0) {
      audioGapsFilled++;
      final padStart = startUs - (timing.padSamples * 1e6 / RadioLink.audioRate).round();
      _placeSamples(Float32List(timing.padSamples ~/ 4), padStart);
    }
    _placeSamples(f, startUs);
    _feedSpectrum(f, startUs);
  }

  // Estima o jitter instantâneo (ms) como o quanto a chegada se afasta do relógio contínuo do áudio.
  double _estimateJitterMs(int arrivalUs) {
    final off = _timeline.offsetUs;
    if (off == null) return 0;
    final endUs = off + _timeline.samples * 1e6 / RadioLink.audioRate;
    return ((arrivalUs - endUs).abs() / 1000.0).clamp(0.0, 500.0);
  }

  /// Escreve [f] (amostras a 12 kHz) no buffer do slot correspondente à hora de captura [startUs].
  void _placeSamples(Float32List f, int startUs) {
    final slotUs = (mode.slotSeconds * 1e6).round();
    final slotSamples = _slotBuf.length;
    var idx = startUs ~/ slotUs;
    var pos = ((startUs - idx * slotUs) * 12000 / 1e6).round();
    if (idx != _bufSlot) {
      if (idx < _bufSlot) return; // amostras de um slot já encerrado
      _rotateSlot(idx);
    }
    var off = 0;
    while (off < f.length) {
      if (pos >= slotSamples) {
        idx++;
        pos -= slotSamples;
        _rotateSlot(idx);
      }
      final take = min(slotSamples - pos, f.length - off);
      if (take <= 0) break;
      if (pos > _slotWrite) {
        _slotBuf.fillRange(_slotWrite, pos, 0); // preenche lacunas com silêncio
      }
      _slotBuf.setRange(pos, pos + take, f, off);
      if (pos + take > _slotWrite) _slotWrite = pos + take;
      off += take;
      pos += take;
    }
    _maybeDecode();
  }

  void _rotateSlot(int idx) {
    _bufSlot = idx;
    _slotWrite = 0;
    _decodedThisSlot = false;
  }

  /// Dispara a decodificação quando o **áudio** do slot atinge o instante configurado do modo.
  void _maybeDecode() {
    if (_decodedThisSlot || !monitoring || !mode.implemented || _bufSlot < 0) return;
    if (_slotWrite < mode.decodeAtSeconds * 12000) return;
    _decodedThisSlot = true;
    if (_bufSlot == _lastTxSlot) return; // slot em que transmitimos: nada a decodificar
    _runDecode(_bufSlot);
  }

  // ------------------------------------------------------------------ waterfall

  void _feedSpectrum(Float32List f, int startUs) {
    _lastAudioMs = startUs ~/ 1000;
    var off = 0;
    while (off < f.length) {
      final take = min(f.length - off, kWfNfft - _specFill);
      _specRing.setRange(_specFill, _specFill + take, f, off);
      _specFill += take;
      off += take;
      _specSince += take;
      if (_specFill == kWfNfft) {
        if (_specSince >= 1800) {
          _computeSpectrumRow();
          _specSince = 0;
        }
        _specRing.setRange(0, kWfNfft - 1024, _specRing, 1024); // desliza a janela
        _specFill = kWfNfft - 1024;
      }
    }
  }

  void _computeSpectrumRow() {
    final db = codec.spectrum(_specRing, kWfNfft);
    if (db.length < kWfBins) return;
    waterfall.pushRow(db, _lastAudioMs, auto: settings.wfAuto, gain: settings.wfGain, zero: settings.wfZero);
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

  // ================================================================== relógio / slots

  void _tick() {
    final t = now();
    final idx = slotIndexAt(t);
    final sec = secondsIntoSlot(t);

    // início de TX (relógio de parede: a transmissão é alinhada ao UTC)
    if (txEnabled && !transmitting && !tuning && idx % 2 == txParity && idx != _lastTxSlot && sec < 2.0) {
      _startTx(idx, sec);
    }
    clockTick.value++;
  }

  // ================================================================== decodificação

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
      if (r.snrDb > -12) {
        _dtSamples.add(r.dtSec);
        if (_dtSamples.length > 60) _dtSamples.removeAt(0);
      }
    }
    fresh.sort((a, b) => a.freq.compareTo(b.freq));
    decodes.addAll(fresh);
    if (decodes.length > 800) decodes.removeRange(0, decodes.length - 800);
    decodesLastSlot = fresh.length;

    // Alerta: alguém me respondeu/chamou neste slot
    final toMe = fresh.where((d) => d.toMe).toList();
    if (toMe.isNotEmpty) {
      final d = toMe.first;
      lastReplyText = d.message;
      lastReplyAt = now();
      alerts.show(AlertKind.reply, '${d.senderCall ?? 'Estação'} respondeu!', '${d.message}   (${d.snr.round()} dB)');
    }

    // auto-sequência: só reage à primeira mensagem dirigida a mim neste slot
    if (settings.autoSeq) {
      for (final d in fresh) {
        if (!d.toMe) continue;
        final ev = qso.onDecode(d, slotParity: parity);
        if (qso.txParity != null) txParity = qso.txParity!;
        if (!settings.holdTxFreq && qso.dxCall.isNotEmpty) {
          settings.txFreq = d.freq.round(); // transmite na frequência do correspondente
        }
        if (ev == QsoEvent.complete) {
          _finishQso(); // registra; o 73 final (Tx5) ainda será transmitido
        } else if (ev == QsoEvent.finished) {
          _finishQso();
          txEnabled = false; // a outra estação encerrou com 73: nada mais a transmitir
          qso.clear();
        }
        break;
      }
    }
    notifyListeners();
  }

  /// Mediana do DT das mensagens fortes recentes (s), ou `null` se houver poucas amostras.
  /// Um valor consistentemente ≠ 0 indica relógio desajustado (veja [calibrateClockFromDt]).
  double? get dtMedianSeconds {
    if (_dtSamples.length < 5) return null;
    final s = List<double>.of(_dtSamples)..sort();
    return s[s.length ~/ 2];
  }

  /// Ajusta a compensação do relógio para zerar o DT mediano observado.
  /// Se os sinais aparecem atrasados (DT > 0), nosso relógio está adiantado: subtrai-se o DT.
  /// Retorna o ajuste aplicado (ms) ou `null` se não há dados suficientes.
  int? calibrateClockFromDt() {
    final m = dtMedianSeconds;
    if (m == null) return null;
    final adj = (-m * 1000).round();
    settings.clockOffsetMs += adj;
    settings.save();
    _dtSamples.clear();
    notifyListeners();
    return adj;
  }

  // ================================================================== QSO e logbook

  QsoRecord _draftFromQso() {
    // frequência de RF = dial (rádio) + tom de áudio de TX
    final freq = (radio?.state.freqHz ?? dialFrequency ?? 0) + settings.txFreq;
    final pwr = radio?.state.rfPower;
    return QsoRecord(
      call: qso.dxCall,
      grid: qso.dxGrid,
      timeOn: qso.started ?? now(),
      timeOff: now(),
      freqHz: freq,
      mode: mode.id,
      rstSent: qso.rptSent,
      rstRcvd: qso.rptRcvd,
      myCall: settings.callsign,
      myGrid: settings.grid,
      // IC-705: 0..255 corresponde a 0..10 W (5 W com bateria); valor aproximado.
      txPowerW: pwr == null ? null : double.parse((pwr * 10 / 255).toStringAsFixed(1)),
    );
  }

  void _finishQso() {
    if (qso.dxCall.isEmpty) return;
    final draft = _draftFromQso();
    lastQsoCall = qso.dxCall;
    lastQsoAt = now();
    alerts.show(AlertKind.qsoComplete, 'QSO completo com ${qso.dxCall}!',
        settings.autoLog ? 'Registrado no logbook.' : 'Confirme o registro no logbook.');
    if (settings.autoLog) {
      commitLog(draft);
    } else {
      pendingLog.value = draft; // a interface abre o diálogo de confirmação
    }
  }

  /// Grava [r] no logbook (após confirmação) e limpa o rascunho pendente.
  Future<void> commitLog(QsoRecord r) async {
    pendingLog.value = null;
    await qsoLog.add(r);
    txLog.add('QSO registrado com ${r.call}');
    notifyListeners();
  }

  /// Descarta o rascunho de log pendente.
  void discardPendingLog() {
    pendingLog.value = null;
  }

  /// Registro manual do QSO atual (botão "Registrar QSO").
  void logQsoNow() {
    if (qso.dxCall.isEmpty) return;
    pendingLog.value = _draftFromQso();
  }

  // ================================================================== transmissão

  void _startTx(int slotIdx, double secIntoSlot) {
    final r = radio;
    if (r == null || r.status != LinkStatus.connected) {
      txEnabled = false;
      lastError = 'Rádio desconectado – TX desativado.';
      notifyListeners();
      return;
    }
    if (!mode.implemented) {
      txEnabled = false;
      lastError = 'Modo ${mode.label} sem suporte a transmissão.';
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
    final lead = (mode.txStartOffset * RadioLink.audioRate).round();
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
    alerts.show(AlertKind.txStart, 'Transmitindo', '$text  ·  ${settings.txFreq} Hz');
    if (r is SimRadio) r.heardTransmission(text, settings.txFreq.toDouble());
    r.setPtt(true);
    _txTimer?.cancel();
    _txTimer = Timer.periodic(const Duration(milliseconds: 20), (_) => _txStep());
    notifyListeners();
  }

  /// Envia ao rádio o áudio de TX em tempo real: a posição enviada acompanha o relógio do slot
  /// com folga de 120 ms (evita *underrun*) mais o avanço configurado `txAdvanceMs`.
  void _txStep() {
    final r = radio;
    final pcm = _txPcm;
    if (r == null || pcm == null || r.status != LinkStatus.connected) {
      stopTx();
      return;
    }
    final elapsed = now().difference(_txSlotStart!).inMicroseconds / 1e6;
    final ahead = 0.12 + settings.txAdvanceMs / 1000.0;
    final target = ((elapsed + ahead) * RadioLink.audioRate).floor().clamp(0, pcm.length);
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
    // Após enviar 73, encerra o QSO; em QSO normal repete a mensagem atual até haver resposta.
    if (qso.txIndex == 5 && qso.dxCall.isNotEmpty) {
      if (!qso.completed) _finishQso();
      txEnabled = false;
      qso.clear();
    } else if (qso.dxCall.isNotEmpty && _txCount >= 12) {
      txEnabled = false;
      lastError = 'Sem resposta de ${qso.dxCall}: TX desativado.';
    }
    notifyListeners();
  }

  /// Interrompe a TX/Tune: solta o PTT e limpa os buffers.
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

  /// "Tune": emite uma portadora de áudio contínua (ajuste de antena/potência) por até 10 s.
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
    final started = now();
    _tuneTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (now().difference(started).inMilliseconds > 10000) {
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
