/// Rádio simulado para desenvolvimento/testes sem hardware.
///
/// Gera áudio de 48 kHz com ruído branco e sinais FT8/FT4 **reais** (codificados com a mesma
/// biblioteca nativa), alinhados ao relógio UTC, e responde às transmissões do usuário (veja `sim_script.dart`;
/// roteiros A e B), permitindo exercitar decodificação, QSO automático e TX de ponta a ponta.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../core/ftx_native.dart';
import '../radio/civ.dart';
import '../radio/radio_link.dart';
import 'sim_script.dart';

/// Rádio simulado: gera áudio com ruído e sinais FT8/FT4 reais (codificados com a ft8_lib),
/// responde às chamadas do usuário e permite testar toda a interface sem um rádio.
class SimRadio implements RadioLink {
  SimRadio({required this.codec, required this.protocol, required this.myCall, required this.clock});

  final FtxCodec codec;
  final FtxProtocol Function() protocol;
  final String Function() myCall;
  final DateTime Function() clock;

  @override
  final RadioState state = RadioState()
    ..freqHz = 14074000
    ..mode = 1
    ..filter = 1
    ..dataMode = true
    ..rfPower = 128
    ..preamp = 0
    ..att = 0;

  final _audio = StreamController<Int16List>.broadcast();
  final _changes = StreamController<void>.broadcast();
  LinkStatus _status = LinkStatus.disconnected;
  Timer? _timer;
  final Random _rnd = Random(7);

  static const _rate = 48000;
  int _lastEmitUs = 0;
  int _slotIdx = -1;
  Float32List? _slotBuf; // 12 kHz

  /// Respostas das estações ao usuário, a transmitir no **próximo** período (veja [simReplyTo]).
  final List<SimReply> _pendingReplies = [];

  /// Rodízio de qual estação responde quando o usuário chama CQ.
  int _cqCounter = 0;

  /// Quantas respostas o simulador já enviou ao usuário (para a interface/testes).
  int repliesSent = 0;

  @override
  LinkStatus get status => _status;
  @override
  String get statusText => _status == LinkStatus.connected ? 'Simulador ativo' : 'Simulador parado';
  @override
  Stream<Int16List> get rxAudio => _audio.stream;
  @override
  Stream<void> get changes => _changes.stream;
  @override
  int? get pingMs => 5;
  @override
  int get lostPackets => 0;

  @override
  Future<void> connect() async {
    _status = LinkStatus.connected;
    _lastEmitUs = clock().microsecondsSinceEpoch;
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) => _emit());
    _changes.add(null);
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _status = LinkStatus.disconnected;
    _changes.add(null);
  }

  @override
  void setPtt(bool on) {
    state.ptt = on;
    if (!on) _flushTxToReply();
    _changes.add(null);
  }

  @override
  void setFrequency(int hz) {
    state.freqHz = hz;
    _changes.add(null);
  }

  @override
  void setUsbData() {
    state
      ..mode = 1
      ..dataMode = true;
    _changes.add(null);
  }

  @override
  void setMode(int mode, {int filter = 1}) {
    state
      ..mode = mode
      ..filter = filter;
    _changes.add(null);
  }

  @override
  void setDataMode(bool on, {int filter = 1}) {
    state.dataMode = on;
    _changes.add(null);
  }

  @override
  void setRfPower(int raw) {
    state.rfPower = raw;
    _changes.add(null);
  }

  @override
  void setPreamp(int value) {
    state.preamp = value;
    _changes.add(null);
  }

  @override
  void setAtt(int db) {
    state.att = db;
    _changes.add(null);
  }

  @override
  void requestState() => _changes.add(null);

  /// Simula uma alteração feita *no painel do rádio* (botão de sintonia, tecla MODE...),
  /// para testar a sincronização rádio -> app sem hardware.
  void radioSideChange({int? freqHz, int? mode, bool? data, int? rfPower}) {
    if (freqHz != null) state.freqHz = freqHz;
    if (mode != null) state.mode = mode;
    if (data != null) state.dataMode = data;
    if (rfPower != null) state.rfPower = rfPower;
    _changes.add(null);
  }

  @override
  void sendCiv(Uint8List frame) {}
  @override
  void sendTxAudio(Int16List pcm) {}

  String? _lastTxText;

  /// O motor informa o que foi transmitido, para a estação simulada responder no próximo slot.
  void heardTransmission(String text, double freq) {
    _lastTxText = text;
  }

  void _flushTxToReply() {
    final t = _lastTxText;
    if (t == null) return;
    _lastTxText = null;
    final reply = simReplyTo(t, myCall(), cqCounter: _cqCounter);
    if (reply != null) {
      if (t.trim().toUpperCase().startsWith('CQ')) _cqCounter++;
      _pendingReplies.add(reply);
    }
  }

  Float32List _buildSlot(int slotIdx) {
    final p = protocol();
    final slotSamples = (p.slotSeconds * 12000).round();
    final buf = Float32List(slotSamples);
    void mix(String text, double freq, double snrDb) {
      final tones = codec.encode(text, p);
      if (tones == null) return;
      final wave = codec.synth(tones, p, freq, 12000);
      // amplitude: ruído σ = 0.05 em 48 kHz => potência em 2500 Hz = σ² * 2500/24000
      final noiseP = 0.05 * 0.05 * 2500 / 24000;
      final amp = sqrt(2 * noiseP * pow(10, snrDb / 10));
      final start = (0.5 * 12000).round() + ((_rnd.nextDouble() - 0.5) * 0.3 * 12000).round();
      for (var i = 0; i < wave.length && start + i < slotSamples; i++) {
        if (start + i >= 0) buf[start + i] += wave[i] * amp;
      }
    }

    // 1) Respostas ao usuário (prioridade): a estação responde na SUA frequência, com sinal forte
    //    o bastante para ser sempre decodificado (o objetivo é ensinar o fluxo do QSO).
    final replying = <String>{};
    for (final r in _pendingReplies) {
      mix(r.text, r.station.freq, max(r.station.snr, -8));
      replying.add(r.station.call);
      repliesSent++;
    }
    _pendingReplies.clear();

    // 2) Estações de fundo: as "alwaysCq" chamam CQ em todo período; as demais conversam
    //    aleatoriamente entre si. Quem está respondendo ao usuário não transmite outra coisa.
    for (final s in kSimStations) {
      if (replying.contains(s.call)) continue;
      final String text;
      if (s.alwaysCq) {
        text = 'CQ ${s.call} ${s.grid}';
      } else {
        if (_rnd.nextDouble() > 0.6) continue;
        if (_rnd.nextDouble() < 0.4) {
          text = 'CQ ${s.call} ${s.grid}';
        } else {
          final other = kSimStations[_rnd.nextInt(kSimStations.length)];
          if (other.call == s.call) continue;
          final rpt = ['-10', '-05', '+02', 'R-12', 'RR73', '73'][_rnd.nextInt(6)];
          text = '${other.call} ${s.call} $rpt';
        }
      }
      mix(text, s.freq, s.snr + (_rnd.nextDouble() - 0.5) * 3);
    }
    return buf;
  }

  double _gauss() {
    final u1 = 1 - _rnd.nextDouble(), u2 = _rnd.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  void _emit() {
    final nowUs = clock().microsecondsSinceEpoch;
    var n = ((nowUs - _lastEmitUs) * _rate / 1e6).floor();
    if (n <= 0) return;
    if (n > _rate) n = _rate ~/ 5;
    final startUs = _lastEmitUs;
    _lastEmitUs += (n * 1e6 / _rate).round();
    final out = Int16List(n);
    final p = protocol();
    final slotUs = (p.slotSeconds * 1e6).round();
    for (var i = 0; i < n; i++) {
      final tUs = startUs + (i * 1e6 / _rate).round();
      final idx = tUs ~/ slotUs;
      if (idx != _slotIdx || _slotBuf == null) {
        _slotIdx = idx;
        _slotBuf = _buildSlot(idx);
      }
      final posSamples12k = ((tUs - idx * slotUs) * 12000 / 1e6);
      final j = posSamples12k.floor();
      double s = 0;
      final b = _slotBuf!;
      if (j >= 0 && j + 1 < b.length) {
        final f = posSamples12k - j;
        s = b[j] * (1 - f) + b[j + 1] * f;
      }
      final v = (s + 0.05 * _gauss()) * 32767;
      out[i] = v.clamp(-32768, 32767).round();
    }
    if (!state.ptt) _audio.add(out);
  }
}
