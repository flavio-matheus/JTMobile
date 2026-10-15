// Teste do cliente de rede Icom contra um "rádio" falso que segue o protocolo conforme o
// projeto de referência (kappanhang). Valida handshake, login, abertura dos fluxos, CI-V e áudio.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ft_mobile/radio/civ.dart';
import 'package:ft_mobile/radio/icom_link.dart';
import 'package:ft_mobile/radio/radio_link.dart';

Uint8List hdr(int len, int type, int seq, int radioSid, int clientSid) {
  final d = Uint8List(len);
  final b = ByteData.sublistView(d);
  b.setUint32(0, len, Endian.little);
  b.setUint16(4, type, Endian.little);
  b.setUint16(6, seq, Endian.little);
  b.setUint32(8, radioSid);
  b.setUint32(12, clientSid);
  return d;
}

class FakeRadio {
  static const sid = 0x01020304;
  late RawDatagramSocket control, serial, audio;
  final received = <String, List<Uint8List>>{'control': [], 'serial': [], 'audio': []};
  final addr = <String, Datagram>{};
  int audioTxPackets = 0;
  int serialSeq = 1;
  int audioSeq = 1;
  Timer? audioTimer;
  bool authSent = false;
  final authId = [1, 2, 3, 4, 5, 6];
  String? loginUser;

  Future<void> start() async {
    control = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 50001);
    serial = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 50002);
    audio = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 50003);
    control.listen((e) => _on(e, control, 'control'));
    serial.listen((e) => _on(e, serial, 'serial'));
    audio.listen((e) => _on(e, audio, 'audio'));
  }

  void stop() {
    audioTimer?.cancel();
    control.close();
    serial.close();
    audio.close();
  }

  void _on(RawSocketEvent e, RawDatagramSocket s, String name) {
    if (e != RawSocketEvent.read) return;
    Datagram? d;
    while ((d = s.receive()) != null) {
      final r = Uint8List.fromList(d!.data);
      received[name]!.add(r);
      addr[name] = d;
      _handle(s, name, r, d);
    }
  }

  void _send(RawDatagramSocket s, Datagram to, Uint8List data) => s.send(data, to.address, to.port);

  void _handle(RawDatagramSocket s, String name, Uint8List r, Datagram from) {
    final bd = ByteData.sublistView(r);
    final clientSid = r.length >= 12 ? bd.getUint32(8) : 0;
    final type = r.length >= 6 ? r[4] | (r[5] << 8) : 0;
    if (r.length == 16 && type == 0x03) {
      _send(s, from, hdr(16, 0x04, 0, sid, clientSid));
      return;
    }
    if (r.length == 16 && type == 0x06) {
      _send(s, from, hdr(16, 0x06, 1, sid, clientSid));
      if (name == 'audio') _startAudio(s, from, clientSid);
      return;
    }
    if (r.length == 21 && type == 0x07 && r[16] == 0) {
      final p = Uint8List.fromList(r);
      p[16] = 1;
      ByteData.sublistView(p).setUint32(8, sid);
      ByteData.sublistView(p).setUint32(12, clientSid);
      _send(s, from, p);
      return;
    }
    if (name == 'control') {
      if (r.length == 128) {
        loginUser = String.fromCharCodes(r.sublist(64, 80).where((b) => b != 0));
        final p = hdr(96, 0, 1, sid, clientSid);
        p.setRange(26, 32, authId);
        _send(s, from, p);
      } else if (r.length == 64) {
        final p = hdr(64, 0, 5, sid, clientSid);
        p[21] = r[21];
        _send(s, from, p);
        if (r[21] == 0x05 && !authSent) {
          authSent = true;
          final a8 = hdr(168, 0, 6, sid, clientSid);
          a8[0] = 0xA8;
          a8.setRange(66, 82, List.generate(16, (i) => i + 1));
          _send(s, from, a8);
        }
      } else if (r.length == 144) {
        final p = hdr(144, 0, 7, sid, clientSid);
        p[0] = 0x90;
        p[96] = 1;
        p.setRange(64, 70, 'IC-705'.codeUnits);
        p.setRange(26, 32, authId);
        _send(s, from, p);
      }
    } else if (name == 'serial') {
      if (r.length > 21 && r[16] == 0xC1) {
        final l = r[17];
        final civ = r.sublist(21, 21 + l);
        _civReply(s, from, clientSid, civ);
      }
    } else if (name == 'audio') {
      if (r.length == 1388 || r.length == 580) audioTxPackets++;
    }
  }

  void _civReply(RawDatagramSocket s, Datagram to, int clientSid, Uint8List req) {
    if (req.length < 6) return;
    final cmd = req[4];
    List<int>? data;
    if (cmd == 0x03) {
      data = [0xFE, 0xFE, 0xE0, 0xA4, 0x03, ...Civ.encodeFreq(14074000), 0xFD];
    } else if (cmd == 0x04) {
      data = [0xFE, 0xFE, 0xE0, 0xA4, 0x04, 0x01, 0x01, 0xFD];
    } else if (cmd == 0x15 && req[5] == 0x02) {
      data = [0xFE, 0xFE, 0xE0, 0xA4, 0x15, 0x02, 0x01, 0x20, 0xFD];
    }
    if (data == null) return;
    final p = hdr(0x15 + data.length, 0, serialSeq++, sid, clientSid);
    p[16] = 0xC1;
    p[17] = data.length;
    p.setRange(21, 21 + data.length, data);
    _send(s, to, p);
  }

  void _startAudio(RawDatagramSocket s, Datagram to, int clientSid) {
    audioTimer?.cancel();
    audioTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      for (final part in [1364, 556]) {
        final total = 24 + part;
        final p = hdr(total, 0, audioSeq++ & 0xFFFF, sid, clientSid);
        final bd = ByteData.sublistView(p);
        for (var i = 0; i < part ~/ 2; i++) {
          bd.setInt16(24 + i * 2, (i % 2 == 0) ? 1000 : -1000, Endian.little);
        }
        _send(s, to, p);
      }
    });
  }
}

void main() {
  test('conecta, autentica, lê frequência e recebe áudio', () async {
    final fake = FakeRadio();
    await fake.start();
    final radio = IcomNetworkRadio(ip: '127.0.0.1', username: 'beer', password: 'beerbeer');
    var samples = 0;
    final sub = radio.rxAudio.listen((p) => samples += p.length);
    try {
      await radio.connect().timeout(const Duration(seconds: 12));
      expect(radio.status, LinkStatus.connected, reason: radio.statusText);
      expect(fake.loginUser, isNotNull);

      // CI-V: o app pediu frequência/modo ao conectar
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(radio.state.freqHz, 14074000);
      expect(radio.state.mode, 1);

      // S-meter via polling
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(radio.state.sMeter, 120);

      // áudio de RX (1920 bytes = 960 amostras por 20 ms)
      expect(samples, greaterThan(960 * 5));

      // TX: 40 ms de áudio => 2 blocos de 20 ms => 4 pacotes
      radio.sendTxAudio(Int16List(1920));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(fake.audioTxPackets, 4);
    } finally {
      await sub.cancel();
      await radio.disconnect();
      fake.stop();
    }
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('falha com mensagem clara se o rádio não responde', () async {
    final radio = IcomNetworkRadio(ip: '127.0.0.1', username: 'x', password: 'y');
    try {
      await radio.connect().timeout(const Duration(seconds: 15));
      expect(radio.status, isNot(LinkStatus.connected));
      expect(radio.statusText, contains('não respondeu'));
    } finally {
      await radio.disconnect();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
