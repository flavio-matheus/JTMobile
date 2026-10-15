import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../core/ftx_native.dart';
import '../radio/civ.dart';
import '../radio/radio_link.dart';

/// Estação fictícia do simulador.
class _SimStation {
  _SimStation(this.call, this.grid, this.freq, this.snr, this.cqProbability);
  final String call;
  final String grid;
  final double freq;
  final double snr;
  final double cqProbability;
}

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
    ..dataMode = true;

  final _audio = StreamController<Int16List>.broadcast();
  final _changes = StreamController<void>.broadcast();
  LinkStatus _status = LinkStatus.disconnected;
  Timer? _timer;
  final Random _rnd = Random(7);

  static const _rate = 48000;
  int _lastEmitUs = 0;
  int _slotIdx = -1;
  Float32List? _slotBuf; // 12 kHz
  final List<String> _pendingReplies = [];
  double _replyFreq = 1500;

  final List<_SimStation> _stations = [
    _SimStation('PY2SIM', 'GG66', 612, 4, 0.5),
    _SimStation('K1ABC', 'FN42', 944, -3, 0.8),
    _SimStation('EA3XYZ', 'JN11', 1210, -9, 0.6),
    _SimStation('JA1DEF', 'PM95', 1732, -14, 0.5),
    _SimStation('LU5GHI', 'GF05', 2105, -6, 0.7),
    _SimStation('DL2JKL', 'JO62', 2480, -17, 0.4),
    _SimStation('ZS6MNO', 'KG44', 2760, -21, 0.3),
    _SimStation('VK3PQR', 'QF22', 372, -12, 0.3),
  ];

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
  void setUsbData() {}
  @override
  void sendCiv(Uint8List frame) {}
  @override
  void sendTxAudio(Int16List pcm) {}

  String? _lastTxText;
  double? _lastTxFreq;

  /// O motor informa o que foi transmitido, para a estação simulada responder no próximo slot.
  void heardTransmission(String text, double freq) {
    _lastTxText = text;
    _lastTxFreq = freq;
  }

  void _flushTxToReply() {
    final t = _lastTxText;
    if (t == null) return;
    _lastTxText = null;
    final me = myCall();
    final tok = t.split(' ');
    String? reply;
    if (tok.first == 'CQ') {
      reply = '$me PY2SIM GG66';
    } else if (tok.length >= 3 && tok[1] == me) {
      final dx = tok[0];
      final last = tok[2];
      if (dx == 'PY2SIM') {
        if (RegExp(r'^[A-R]{2}\d{2}$').hasMatch(last) && last != 'RR73') {
          reply = '$me PY2SIM -08';
        } else if (RegExp(r'^[+-]\d{2}$').hasMatch(last)) {
          reply = '$me PY2SIM R-09';
        } else if (RegExp(r'^R[+-]\d{2}$').hasMatch(last)) {
          reply = '$me PY2SIM RR73';
        }
      }
    }
    if (reply != null) {
      _pendingReplies.add(reply);
      _replyFreq = _lastTxFreq ?? 1500;
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

    final me = myCall();
    // Respostas ao usuário (prioridade)
    for (final r in _pendingReplies) {
      mix(r, _replyFreq, -5);
    }
    _pendingReplies.clear();
    for (final s in _stations) {
      if (_rnd.nextDouble() > 0.75) continue;
      final String text;
      if (_rnd.nextDouble() < s.cqProbability) {
        text = 'CQ ${s.call} ${s.grid}';
      } else {
        final other = _stations[_rnd.nextInt(_stations.length)];
        if (other.call == s.call) continue;
        final rpt = ['-10', '-05', '+02', 'R-12', 'RR73', '73'][_rnd.nextInt(6)];
        text = '${other.call} ${s.call} $rpt';
      }
      mix(text, s.freq, s.snr + (_rnd.nextDouble() - 0.5) * 4);
    }
    // de vez em quando alguém chama o usuário
    if (me.isNotEmpty && _rnd.nextDouble() < 0.12) {
      mix('$me VK3PQR QF22', 372, -12);
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
