// Cliente do protocolo de rede UDP dos rádios Icom (servidor "RS-BA1" embutido no IC-705).
// É o mesmo protocolo usado pelo aplicativo Icom RS-MS1A. Implementação em Dart baseada na
// análise do projeto kappanhang (MIT, https://github.com/nonoo/kappanhang).
//
// Três fluxos UDP: controle (50001, login/autenticação), serial (50002, CI-V) e áudio (50003).
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'civ.dart';
import 'passcode.dart';
import 'radio_link.dart';

const int _portControl = 50001;
const int _portSerial = 50002;
const int _portAudio = 50003;
const int _txBufferMs = 300;

int _be32(Uint8List b, int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
int _le16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

class IcomException implements Exception {
  IcomException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reordena pacotes recebidos e pede retransmissão dos que faltam.
class _RxSeq {
  _RxSeq({required this.deliver, required this.requestRetransmit, this.onLoss});
  final void Function(Uint8List data) deliver;
  final void Function(int seq) requestRetransmit;
  final void Function(int count)? onLoss;

  int? _expected;
  final Map<int, Uint8List> _buf = {};
  final Set<int> _requested = {};
  Timer? _gapTimer;

  void add(int seq, Uint8List data) {
    _expected ??= seq;
    final diff = (seq - _expected!) & 0xFFFF;
    if (diff >= 0x8000) return; // atrasado/duplicado
    if (diff == 0) {
      deliver(data);
      _expected = (seq + 1) & 0xFFFF;
      _requested.remove(seq);
      _flush();
    } else if (diff < 300) {
      _buf[seq] = data;
      for (var i = 0; i < diff && i < 10; i++) {
        final m = (_expected! + i) & 0xFFFF;
        if (!_buf.containsKey(m) && _requested.add(m)) requestRetransmit(m);
      }
      _gapTimer ??= Timer(const Duration(milliseconds: 120), _giveUp);
    } else {
      _buf.clear();
      _requested.clear();
      deliver(data);
      _expected = (seq + 1) & 0xFFFF;
    }
  }

  void _flush() {
    while (_buf.containsKey(_expected)) {
      final d = _buf.remove(_expected)!;
      _requested.remove(_expected);
      deliver(d);
      _expected = (_expected! + 1) & 0xFFFF;
    }
    if (_buf.isEmpty) {
      _gapTimer?.cancel();
      _gapTimer = null;
    }
  }

  void _giveUp() {
    _gapTimer = null;
    if (_buf.isEmpty) return;
    // Pula para o menor sequencial disponível.
    int? best;
    var bestDiff = 0x10000;
    for (final k in _buf.keys) {
      final d = (k - _expected!) & 0xFFFF;
      if (d < bestDiff) {
        bestDiff = d;
        best = k;
      }
    }
    if (best != null) {
      onLoss?.call(bestDiff);
      _expected = best;
      _flush();
    }
    if (_buf.isNotEmpty) _gapTimer = Timer(const Duration(milliseconds: 120), _giveUp);
  }

  void dispose() {
    _gapTimer?.cancel();
    _buf.clear();
  }
}

/// Um fluxo UDP (controle, serial ou áudio) com o servidor do rádio.
class _UdpStream {
  _UdpStream(this.name, this.host, this.port);

  final String name;
  final InternetAddress host;
  final int port;

  RawDatagramSocket? _sock;
  int localSid = 0;
  int remoteSid = 0;
  bool gotRemoteSid = false;

  /// Cada pacote recebido (exceto ping e pedidos de retransmissão) passa por aqui.
  void Function(Uint8List r)? onPacket;

  // pkt0: pacotes rastreados enviados (para retransmissão sob demanda)
  int pkt0Seq = 1;
  final LinkedHashMap<int, Uint8List> _txHist = LinkedHashMap();
  Timer? _idleTimer;
  DateTime _lastTracked = DateTime.fromMillisecondsSinceEpoch(0);

  // pkt7: ping
  Timer? _pingTimer;
  int _pingSeq = 0;
  int _pingInner = 0x8304;
  bool pingActive = false;
  int _lastPingSentUs = 0;
  double? latencyMs;

  Completer<Uint8List>? _waiter;
  int _waitLen = 0;
  List<int> _waitPrefix = const [];

  Future<void> open() async {
    final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _sock = s;
    // SID local: 2 últimos octetos do IP local + porta local (como o RS-BA1).
    final ip = await _localIpFor(host);
    localSid = ((ip[2] << 24) | (ip[3] << 16) | (s.port & 0xFFFF)) & 0xFFFFFFFF;
    s.listen((e) {
      if (e != RawSocketEvent.read) return;
      Datagram? d;
      while ((d = s.receive()) != null) {
        if (d!.address != host) continue;
        _onDatagram(Uint8List.fromList(d.data));
      }
    });
  }

  static Future<List<int>> _localIpFor(InternetAddress remote) async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final rp = remote.rawAddress;
      List<int>? any;
      for (final i in ifs) {
        for (final a in i.addresses) {
          final ra = a.rawAddress;
          if (ra[0] == 127) continue;
          any ??= ra;
          if (ra[0] == rp[0] && ra[1] == rp[1] && ra[2] == rp[2]) return ra;
        }
      }
      if (any != null) return any;
    } catch (_) {}
    final r = Random.secure();
    return [10, 0, r.nextInt(256), r.nextInt(256)];
  }

  void send(Uint8List d) {
    _sock?.send(d, host, port);
  }

  void _onDatagram(Uint8List r) {
    if (r.length == 21 && r[1] == 0 && r[2] == 0 && r[3] == 0 && r[4] == 0x07 && r[5] == 0) {
      _handlePing(r);
      return;
    }
    if (r.length >= 16 && r[0] == 0x10 && r[1] == 0 && r[2] == 0 && r[3] == 0 && r[4] == 0x01 && r[5] == 0) {
      _retransmit(_le16(r, 6));
      return;
    }
    if (r.length >= 16 && r[0] == 0x18 && r[1] == 0 && r[2] == 0 && r[3] == 0 && r[4] == 0x01 && r[5] == 0) {
      for (var o = 16; o + 4 <= r.length; o += 4) {
        final start = _le16(r, o), end = _le16(r, o + 2);
        var s = start;
        for (var n = 0; n < 20; n++) {
          _retransmit(s);
          if (s == end) break;
          s = (s + 1) & 0xFFFF;
        }
      }
      return;
    }
    final w = _waiter;
    if (w != null && !w.isCompleted && r.length == _waitLen && _startsWith(r, _waitPrefix)) {
      w.complete(r);
      _waiter = null;
    }
    onPacket?.call(r);
  }

  static bool _startsWith(Uint8List r, List<int> p) {
    for (var i = 0; i < p.length; i++) {
      if (r[i] != p[i]) return false;
    }
    return true;
  }

  Future<Uint8List> expect(int length, List<int> prefix, {Duration timeout = const Duration(seconds: 1)}) {
    final c = Completer<Uint8List>();
    _waiter = c;
    _waitLen = length;
    _waitPrefix = prefix;
    return c.future.timeout(timeout, onTimeout: () {
      _waiter = null;
      throw IcomException('$name: o rádio não respondeu (verifique IP, Wi-Fi e "Network control" no rádio)');
    });
  }

  Uint8List _simple(int type, int seq) {
    final d = Uint8List(16);
    final b = ByteData.sublistView(d);
    b.setUint32(0, 16, Endian.little);
    b.setUint16(4, type, Endian.little);
    b.setUint16(6, seq, Endian.little);
    b.setUint32(8, localSid);
    b.setUint32(12, remoteSid);
    return d;
  }

  /// Cabeçalho de 16 bytes de um pacote de dados de comprimento [len].
  Uint8List header(int len) {
    final d = Uint8List(len);
    final b = ByteData.sublistView(d);
    b.setUint32(0, len, Endian.little);
    b.setUint32(8, localSid);
    b.setUint32(12, remoteSid);
    return d;
  }

  void _sendTwice(Uint8List d) {
    send(d);
    send(d);
  }

  /// "Are you there" -> "I am here" -> "Are you ready" -> "I am ready".
  Future<void> handshake() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final f = expect(16, [0x10, 0, 0, 0, 0x04, 0]);
        _sendTwice(_simple(0x03, 0));
        final r = await f;
        remoteSid = _be32(r, 8);
        gotRemoteSid = true;
        break;
      } on IcomException {
        if (attempt == 2) rethrow;
      }
    }
    final f2 = expect(16, [0x10, 0, 0, 0, 0x06, 0, 0x01, 0]);
    _sendTwice(_simple(0x06, 1));
    await f2;
  }

  // ---- pkt0 (rastreado)

  void sendTracked(Uint8List d) {
    ByteData.sublistView(d).setUint16(6, pkt0Seq & 0xFFFF, Endian.little);
    _txHist[pkt0Seq & 0xFFFF] = d;
    while (_txHist.length > 600) {
      _txHist.remove(_txHist.keys.first);
    }
    send(d);
    pkt0Seq = (pkt0Seq + 1) & 0xFFFF;
    final idle = d.length == 16 && d[4] == 0 && d[5] == 0;
    if (!idle) _lastTracked = DateTime.now();
  }

  void _retransmit(int seq) {
    final d = _txHist[seq];
    if (d != null) {
      final copy = Uint8List.fromList(d);
      send(copy);
      send(copy);
    } else {
      final idle = _simple(0x00, seq);
      send(idle);
      send(idle);
    }
  }

  void startIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final active = DateTime.now().difference(_lastTracked) < const Duration(seconds: 1);
      if (active || DateTime.now().millisecond < 100) {
        sendTracked(_simple(0x00, 0));
      }
    });
  }

  void requestRetransmit(int seq) {
    final d = _simple(0x01, seq);
    _sendTwice(d);
  }

  // ---- pkt7 (ping)

  void startPing(int firstSeq) {
    _pingSeq = firstSeq;
    _pingInner = 0x8304;
    pingActive = true;
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _sendPing(null, _pingSeq);
      _lastPingSentUs = DateTime.now().microsecondsSinceEpoch;
      _pingSeq = (_pingSeq + 1) & 0xFFFF;
    });
  }

  void _sendPing(List<int>? replyId, int seq) {
    final d = Uint8List(21);
    final b = ByteData.sublistView(d);
    b.setUint32(0, 0x15, Endian.little);
    b.setUint16(4, 0x07, Endian.little);
    b.setUint16(6, seq, Endian.little);
    b.setUint32(8, localSid);
    b.setUint32(12, remoteSid);
    if (replyId == null) {
      d[16] = 0;
      d[17] = Random().nextInt(256);
      d[18] = _pingInner & 0xFF;
      d[19] = (_pingInner >> 8) & 0xFF;
      d[20] = 0x06;
      _pingInner++;
    } else {
      d[16] = 1;
      d.setRange(17, 21, replyId);
    }
    send(d);
  }

  void _handlePing(Uint8List r) {
    final seq = _le16(r, 6);
    if (r[16] == 0) {
      if (pingActive) _sendPing(r.sublist(17, 21), seq);
    } else if (pingActive && name == 'control' && _lastPingSentUs != 0) {
      final ms = (DateTime.now().microsecondsSinceEpoch - _lastPingSentUs) / 1000.0;
      latencyMs = latencyMs == null ? ms : (latencyMs! + ms) / 2;
    }
  }

  Future<void> close() async {
    _idleTimer?.cancel();
    _pingTimer?.cancel();
    pingActive = false;
    if (gotRemoteSid && _sock != null) {
      _sendTwice(_simple(0x05, 0));
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
    _sock?.close();
    _sock = null;
  }
}

bool debugIcom = false;

/// Enlace com o IC-705 via Wi-Fi (protocolo de rede da Icom).
class IcomNetworkRadio implements RadioLink {
  IcomNetworkRadio({required this.ip, required this.username, required this.password});

  final String ip;
  final String username;
  final String password;

  @override
  final RadioState state = RadioState();

  final _audioCtl = StreamController<Int16List>.broadcast();
  final _changeCtl = StreamController<void>.broadcast();

  LinkStatus _status = LinkStatus.disconnected;
  String _statusText = 'Desconectado';
  int _lost = 0;
  bool _want = false;
  Timer? _reauth;
  Timer? _poll;
  Timer? _watchdog;
  DateTime _lastAudio = DateTime.now();
  int _pollTick = 0;

  _UdpStream? _control, _serial, _audio;
  _RxSeq? _serialRx, _audioRx;
  int _authInner = 0;
  List<int> _authId = List.filled(6, 0);
  List<int> _a8Reply = List.filled(16, 0);
  bool _gotA8 = false;
  bool _authOk = false;
  bool _serialAudioReq = false;
  Completer<void>? _streamsOpened;
  int _serialSendSeq = 0;
  int _audioSendSeq = 1;
  final List<int> _civBuf = [];
  final BytesBuilder _txBuf = BytesBuilder();

  @override
  LinkStatus get status => _status;
  @override
  String get statusText => _statusText;
  @override
  Stream<Int16List> get rxAudio => _audioCtl.stream;
  @override
  Stream<void> get changes => _changeCtl.stream;
  @override
  int? get pingMs => _control?.latencyMs?.round();
  @override
  int get lostPackets => _lost;

  void _set(LinkStatus s, String text) {
    _status = s;
    _statusText = text;
    if (!_changeCtl.isClosed) _changeCtl.add(null);
  }

  @override
  Future<void> connect() async {
    _want = true;
    await _session();
  }

  Future<void> _session() async {
    if (!_want) return;
    await _teardown(sendBye: false);
    _set(LinkStatus.connecting, 'Conectando a $ip…');
    try {
      final host = InternetAddress.tryParse(ip) ?? (await InternetAddress.lookup(ip)).first;
      final c = _UdpStream('control', host, _portControl);
      _control = c;
      await c.open();
      await c.handshake();
      c.pkt0Seq = 1;
      c.onPacket = _onControlPacket;

      // Login
      final loginWait = c.expect(96, [0x60, 0, 0, 0, 0, 0, 0x01, 0], timeout: const Duration(seconds: 3));
      _sendLogin(c);
      final lr = await loginWait;
      if (lr[48] == 0xFF && lr[49] == 0xFF && lr[50] == 0xFF && lr[51] == 0xFE) {
        throw IcomException('Usuário/senha inválidos (menu Network User do rádio)');
      }
      _authId = lr.sublist(26, 32);
      c.startPing(2);
      _sendAuth(c, 0x02);
      c.startIdle();
      _sendAuth(c, 0x05);

      _streamsOpened = Completer<void>();
      await _streamsOpened!.future.timeout(const Duration(seconds: 6), onTimeout: () {
        throw IcomException('Tempo esgotado abrindo áudio/serial no rádio (reinicie o Wi-Fi do rádio)');
      });

      _reauth = Timer.periodic(const Duration(minutes: 1), (_) => _sendAuth(c, 0x05));
      _lastAudio = DateTime.now();
      _watchdog = Timer.periodic(const Duration(seconds: 1), (_) => _watch());
      _set(LinkStatus.connected, 'Conectado (IC-705 Wi-Fi)');

      // Estado inicial e polling
      sendCiv(Civ.readFreq());
      sendCiv(Civ.readMode());
      sendCiv(Civ.readDataMode());
      _poll = Timer.periodic(const Duration(milliseconds: 250), (_) => _pollTickFn());
    } catch (e) {
      final msg = e is IcomException ? e.message : 'Erro: $e';
      await _teardown(sendBye: false);
      _set(LinkStatus.error, msg);
      _scheduleReconnect();
    }
  }

  Timer? _reconnectTimer;
  void _scheduleReconnect() {
    if (!_want) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), () {
      if (_want && _status != LinkStatus.connected) _session();
    });
  }

  void _watch() {
    if (_status != LinkStatus.connected) return;
    if (DateTime.now().difference(_lastAudio) > const Duration(seconds: 5)) {
      _set(LinkStatus.error, 'Sem áudio do rádio por 5 s – reconectando');
      _teardown(sendBye: false).then((_) => _scheduleReconnect());
    }
  }

  // ---------------------------------------------------------------- pacotes do controle

  void _sendLogin(_UdpStream c) {
    final d = c.header(0x80);
    final b = ByteData.sublistView(d);
    b.setUint32(16, 0x70);
    d[20] = 0x01;
    d[23] = _authInner & 0xFF;
    d[24] = (_authInner >> 8) & 0xFF;
    final r = Random.secure();
    d[26] = r.nextInt(256);
    d[27] = r.nextInt(256);
    d.setRange(64, 80, icomPasscode(username));
    d.setRange(80, 96, icomPasscode(password));
    d.setRange(96, 104, [0x69, 0x63, 0x6f, 0x6d, 0x2d, 0x70, 0x63, 0x00]); // "icom-pc"
    c.sendTracked(d);
    _authInner++;
  }

  void _sendAuth(_UdpStream c, int magic) {
    final d = c.header(0x40);
    ByteData.sublistView(d).setUint32(16, 0x30);
    d[20] = 0x01;
    d[21] = magic;
    d[23] = _authInner & 0xFF;
    d[24] = (_authInner >> 8) & 0xFF;
    d.setRange(26, 32, _authId);
    c.sendTracked(d);
    _authInner++;
  }

  void _sendRequestStreams(_UdpStream c) {
    final d = c.header(0x90);
    ByteData.sublistView(d).setUint32(16, 0x80);
    d[20] = 0x01;
    d[21] = 0x03;
    d[23] = _authInner & 0xFF;
    d[24] = (_authInner >> 8) & 0xFF;
    d.setRange(26, 32, _authId);
    d.setRange(32, 48, _a8Reply);
    d.setRange(64, 72, [0x49, 0x43, 0x2d, 0x37, 0x30, 0x35, 0x00, 0x00]); // "IC-705"
    d.setRange(96, 112, icomPasscode(username));
    const rate = RadioLink.audioRate;
    d.setRange(112, 120, [0x01, 0x01, 0x04, 0x04, 0x00, 0x00, rate >> 8, rate & 0xFF]);
    d.setRange(120, 124, [0x00, 0x00, rate >> 8, rate & 0xFF]);
    d.setRange(124, 128, [0x00, 0x00, _portSerial >> 8, _portSerial & 0xFF]);
    d.setRange(128, 134, [0x00, 0x00, _portAudio >> 8, _portAudio & 0xFF, 0x00, 0x00]);
    d.setRange(134, 144, [_txBufferMs >> 8, _txBufferMs & 0xFF, 0x01, 0, 0, 0, 0, 0, 0, 0]);
    c.sendTracked(d);
    _authInner++;
  }

  void _maybeRequestStreams() {
    final c = _control;
    if (c == null || _serialAudioReq) return;
    if (_authOk && _gotA8) {
      _serialAudioReq = true;
      _sendRequestStreams(c);
    }
  }

  void _onControlPacket(Uint8List r) {
    final c = _control;
    if (c == null) return;
    switch (r.length) {
      case 168:
        if (r[0] == 0xA8 && r[1] == 0 && r[2] == 0 && r[3] == 0 && r[4] == 0 && r[5] == 0) {
          _a8Reply = r.sublist(66, 82);
          _gotA8 = true;
          _maybeRequestStreams();
        }
        break;
      case 64:
        if (r[0] == 0x40 && r[4] == 0 && r[5] == 0 && r[21] == 0x05) {
          _authOk = true;
          _maybeRequestStreams();
        }
        break;
      case 80:
        if (r[0] == 0x50 && r[4] == 0 && r[5] == 0) {
          if (r[48] == 0xFF && r[49] == 0xFF && r[50] == 0xFF) {
            _fail('Falha de autenticação (reinicie o Wi-Fi do rádio)');
          } else if (r[48] == 0 && r[49] == 0 && r[50] == 0 && r[64] == 0x01) {
            _fail('O rádio desconectou esta sessão');
          }
        }
        break;
      case 144:
        if (r[0] == 0x90 && r[4] == 0 && r[5] == 0 && r[96] == 1 && !(_streamsOpened?.isCompleted ?? true)) {
          c.remoteSid = _be32(r, 8);
          c.localSid = _be32(r, 12);
          _authId = r.sublist(26, 32);
          _openStreams(c.host).then((_) {
            if (!(_streamsOpened?.isCompleted ?? true)) _streamsOpened!.complete();
          }).catchError((Object e) {
            if (!(_streamsOpened?.isCompleted ?? true)) _streamsOpened!.completeError(e);
          });
        }
        break;
    }
  }

  void _fail(String msg) {
    _set(LinkStatus.error, msg);
    _teardown(sendBye: false).then((_) => _scheduleReconnect());
  }

  // ---------------------------------------------------------------- serial e áudio

  Future<void> _openStreams(InternetAddress host) async {
    // serial (CI-V)
    final s = _UdpStream('serial', host, _portSerial);
    _serial = s;
    await s.open();
    await s.handshake();
    s.pkt0Seq = 1;
    _serialRx = _RxSeq(
      deliver: _onSerialData,
      requestRetransmit: s.requestRetransmit,
      onLoss: (n) => _lost += n,
    );
    s.onPacket = (r) {
      final idle = r.length == 16 && r[4] == 0 && r[5] == 0;
      final data = r.length >= 22 && r[16] == 0xC1 && r[0] - 0x15 == r[17];
      if (idle || data) _serialRx?.add(_le16(r, 6), r);
    };
    s.startPing(1);
    s.startIdle();
    _sendSerialOpenClose(s, false);

    // áudio
    final a = _UdpStream('audio', host, _portAudio);
    _audio = a;
    await a.open();
    await a.handshake();
    a.pkt0Seq = 0;
    _audioSendSeq = 1;
    _audioRx = _RxSeq(
      deliver: _onAudioData,
      requestRetransmit: a.requestRetransmit,
      onLoss: (n) => _lost += n,
    );
    a.onPacket = (r) {
      if (r.length >= 580 &&
          r[2] == 0 &&
          r[3] == 0 &&
          r[4] == 0 &&
          r[5] == 0 &&
          ((r[0] == 0x6C && r[1] == 0x05) || (r[0] == 0x44 && r[1] == 0x02))) {
        _audioRx?.add(_le16(r, 6), Uint8List.sublistView(r, 24));
      }
    };
    a.startPing(1);
  }

  void _sendSerialOpenClose(_UdpStream s, bool close) {
    final d = s.header(0x16);
    d[16] = 0xC0;
    d[17] = 0x01;
    d[19] = (_serialSendSeq >> 8) & 0xFF;
    d[20] = _serialSendSeq & 0xFF;
    d[21] = close ? 0x00 : 0x05;
    s.sendTracked(d);
    _serialSendSeq++;
  }

  void _onSerialData(Uint8List r) {
    if (r.length < 22) return; // idle
    _civBuf.addAll(Uint8List.sublistView(r, 21));
    if (_civBuf.length > 512) _civBuf.removeRange(0, _civBuf.length - 512);
    final frames = Civ.parse(_civBuf);
    if (frames.isNotEmpty) {
      // descarta os bytes já consumidos (até o último FD)
      final last = _civBuf.lastIndexOf(0xFD);
      if (last >= 0) _civBuf.removeRange(0, last + 1);
      var changed = false;
      for (final f in frames) {
        if (f.to != civControllerAddress && f.to != 0x00) continue;
        changed |= Civ.apply(state, f);
      }
      if (changed && !_changeCtl.isClosed) _changeCtl.add(null);
    }
  }

  void _onAudioData(Uint8List pcm) {
    _lastAudio = DateTime.now();
    final n = pcm.length ~/ 2;
    final out = Int16List(n);
    final bd = ByteData.sublistView(pcm);
    for (var i = 0; i < n; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little);
    }
    if (!_audioCtl.isClosed) _audioCtl.add(out);
  }

  // ---------------------------------------------------------------- comandos

  @override
  void sendCiv(Uint8List frame) {
    final s = _serial;
    if (s == null || !s.gotRemoteSid) return;
    for (var o = 0; o < frame.length; o += 80) {
      final chunk = frame.sublist(o, min(o + 80, frame.length));
      final d = s.header(0x15 + chunk.length);
      d[16] = 0xC1;
      d[17] = chunk.length;
      d[19] = (_serialSendSeq >> 8) & 0xFF;
      d[20] = _serialSendSeq & 0xFF;
      d.setRange(21, 21 + chunk.length, chunk);
      s.sendTracked(d);
      _serialSendSeq++;
    }
  }

  void _pollTickFn() {
    if (_status != LinkStatus.connected) return;
    _pollTick++;
    if (state.ptt) {
      sendCiv(_pollTick.isEven ? Civ.readPowerMeter() : Civ.readSwr());
    } else {
      sendCiv(Civ.readSMeter());
    }
    if (_pollTick % 8 == 0) sendCiv(Civ.readFreq());
    if (_pollTick % 40 == 4) {
      sendCiv(Civ.readMode());
      sendCiv(Civ.readDataMode());
    }
  }

  @override
  void setPtt(bool on) {
    sendCiv(Civ.setPtt(on));
    state.ptt = on; // otimista; confirmado pela leitura/notificação
    if (!on) {
      state.powerMeter = 0;
      state.swrMeter = 0;
    }
    if (!_changeCtl.isClosed) _changeCtl.add(null);
  }

  @override
  void setFrequency(int hz) {
    sendCiv(Civ.setFreq(hz));
    state.freqHz = hz;
    if (!_changeCtl.isClosed) _changeCtl.add(null);
  }

  @override
  void setUsbData() {
    sendCiv(Civ.setMode(1)); // USB
    sendCiv(Civ.setDataMode(true)); // USB-D
  }

  @override
  void sendTxAudio(Int16List pcm) {
    final a = _audio;
    if (a == null || !a.gotRemoteSid) return;
    _txBuf.add(Uint8List.view(pcm.buffer, pcm.offsetInBytes, pcm.lengthInBytes));
    var all = _txBuf.takeBytes();
    var o = 0;
    while (all.length - o >= 1920) {
      _sendAudioParts(a, Uint8List.sublistView(all, o, o + 1920));
      o += 1920;
    }
    if (o < all.length) _txBuf.add(Uint8List.sublistView(all, o));
  }

  void _sendAudioParts(_UdpStream a, Uint8List chunk) {
    _audioPart(a, 0x056C, chunk.sublist(0, 1364));
    _audioPart(a, 0x0244, chunk.sublist(1364, 1920));
  }

  void _audioPart(_UdpStream a, int total, Uint8List pcm) {
    final d = a.header(24 + pcm.length);
    d[16] = 0x80;
    d[18] = ((_audioSendSeq - 1) >> 8) & 0xFF;
    d[19] = (_audioSendSeq - 1) & 0xFF;
    d[22] = (pcm.length >> 8) & 0xFF;
    d[23] = pcm.length & 0xFF;
    d.setRange(24, 24 + pcm.length, pcm);
    assert(d.length == total);
    a.sendTracked(d);
    _audioSendSeq++;
  }

  // ---------------------------------------------------------------- encerramento

  Future<void> _teardown({required bool sendBye}) async {
    _reauth?.cancel();
    _poll?.cancel();
    _watchdog?.cancel();
    _reauth = _poll = _watchdog = null;
    _serialRx?.dispose();
    _audioRx?.dispose();
    _serialRx = _audioRx = null;
    final c = _control, s = _serial, a = _audio;
    _control = _serial = _audio = null;
    _authOk = false;
    _gotA8 = false;
    _serialAudioReq = false;
    _civBuf.clear();
    _txBuf.clear();
    if (s != null && sendBye) {
      _sendSerialOpenClose(s, true);
    }
    if (c != null && sendBye && c.gotRemoteSid) {
      _sendAuth(c, 0x01);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await s?.close();
    await a?.close();
    await c?.close();
  }

  @override
  Future<void> disconnect() async {
    _want = false;
    _reconnectTimer?.cancel();
    final wasUp = _status == LinkStatus.connected;
    if (wasUp && state.ptt) setPtt(false);
    await _teardown(sendBye: wasUp);
    _set(LinkStatus.disconnected, 'Desconectado');
  }
}
