import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jtmobile/engine/radio_sync.dart';
import 'package:jtmobile/radio/civ.dart';
import 'package:jtmobile/radio/radio_link.dart';

/// Enlace falso que registra o que o app envia e permite simular o rádio.
class FakeLink implements RadioLink {
  @override
  final RadioState state = RadioState()
    ..freqHz = 14074000
    ..mode = 1
    ..dataMode = true
    ..rfPower = 128;
  final sent = <String>[];
  final _c = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _c.stream;
  @override
  Stream<Int16List> get rxAudio => const Stream.empty();
  @override
  LinkStatus get status => LinkStatus.connected;
  @override
  String get statusText => '';
  @override
  int? get pingMs => 1;
  @override
  int get lostPackets => 0;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  void setPtt(bool on) {}
  @override
  void setFrequency(int hz) {
    sent.add('freq:$hz');
    state.freqHz = hz;
  }

  @override
  void setUsbData() {
    sent.add('usbd');
    state.mode = 1;
    state.dataMode = true;
  }

  @override
  void setMode(int mode, {int filter = 1}) {
    sent.add('mode:$mode');
    state.mode = mode;
  }

  @override
  void setDataMode(bool on, {int filter = 1}) {
    sent.add('data:$on');
    state.dataMode = on;
  }

  @override
  void setRfPower(int raw) {
    sent.add('pwr:$raw');
    state.rfPower = raw;
  }

  @override
  void setPreamp(int value) => sent.add('pre:$value');
  @override
  void setAtt(int db) => sent.add('att:$db');
  @override
  void requestState() => sent.add('req');
  @override
  void sendTxAudio(Int16List pcm) {}
  @override
  void sendCiv(Uint8List frame) {}
}

void main() {
  late FakeLink link;
  late List<RadioChange> events;
  late DateTime now;
  late RadioSync sync;

  setUp(() {
    link = FakeLink();
    events = [];
    now = DateTime.utc(2026, 1, 1, 12);
    sync = RadioSync(link: link, onRadioChange: events.add, clock: () => now);
  });

  test('adoptAll entrega o estado do rádio como eventos (política radioFirst)', () {
    sync.adoptAll();
    final fields = events.map((e) => e.field).toSet();
    expect(fields, containsAll([SyncField.frequency, SyncField.mode, SyncField.dataMode, SyncField.rfPower]));
    expect(events.firstWhere((e) => e.field == SyncField.frequency).value, 14074000);
  });

  test('mudança feita no rádio (botão de sintonia) gera evento uma única vez', () {
    sync.adoptAll();
    events.clear();
    link.state.freqHz = 7074000; // usuário girou o botão no rádio
    sync.onLinkChanged();
    expect(events.single.field, SyncField.frequency);
    expect(events.single.value, 7074000);
    events.clear();
    sync.onLinkChanged();
    expect(events, isEmpty);
  });

  test('escrita do app envia ao rádio e não gera eco', () {
    sync.adoptAll();
    events.clear();
    sync.pushFrequency(21074000);
    expect(link.sent.last, 'freq:21074000');
    sync.onLinkChanged();
    expect(events, isEmpty);
  });

  test('resposta atrasada de polling durante a janela de guarda é ignorada', () {
    sync.adoptAll();
    events.clear();
    sync.pushFrequency(21074000);
    link.state.freqHz = 14074000; // chega uma leitura antiga (anterior à escrita)
    sync.onLinkChanged();
    expect(events, isEmpty, reason: 'valor antigo não deve reverter o app');
    // depois da janela, o rádio realmente em 14.074 (usuário mudou lá) vira evento
    now = now.add(const Duration(seconds: 5));
    sync.onLinkChanged();
    expect(events.single.value, 14074000);
  });

  test('pushUsbData e potência; alteração posterior no rádio gera evento', () {
    sync.pushUsbData();
    sync.pushRfPower(100);
    expect(link.sent, containsAll(['usbd', 'pwr:100']));
    events.clear();
    link.state.rfPower = 200; // alterado no rádio depois da janela
    now = now.add(const Duration(seconds: 5));
    sync.onLinkChanged();
    final power = events.where((e) => e.field == SyncField.rfPower).single;
    expect(power.value, 200);
  });
}
