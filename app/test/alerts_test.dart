import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jtmobile/engine/alerts.dart';

class FakePlayer implements AlertPlayer {
  final played = <AlertKind>[];
  final vibrated = <AlertKind>[];
  @override
  Future<void> play(AlertKind kind) async => played.add(kind);
  @override
  Future<void> vibrate(AlertKind kind) async => vibrated.add(kind);
}

void main() {
  group('AlertSounds', () {
    test('todos os alertas geram PCM com a duração e o volume esperados', () {
      for (final k in AlertKind.values) {
        final pcm = AlertSounds.pcm(k);
        final samples = pcm.length ~/ 2;
        final expected = AlertSounds.durationMs(k) * AlertSounds.sampleRate / 1000;
        expect((samples - expected).abs(), lessThan(AlertKind.values.length * 2 + 8), reason: '$k');
        final bd = ByteData.sublistView(pcm);
        var peak = 0;
        for (var i = 0; i < samples; i++) {
          final v = bd.getInt16(i * 2, Endian.little).abs();
          if (v > peak) peak = v;
        }
        expect(peak, inInclusiveRange(8000, 32767), reason: 'volume de $k');
      }
    });

    test('o alerta de resposta é distinto do de TX e do de QSO completo', () {
      expect(AlertSounds.pcm(AlertKind.reply), isNot(AlertSounds.pcm(AlertKind.txStart)));
      expect(AlertSounds.durationMs(AlertKind.qsoComplete), greaterThan(AlertSounds.durationMs(AlertKind.reply)));
    });
  });

  group('AlertCenter', () {
    test('show: define o alerta atual, toca som, vibra e avança o flash', () {
      final p = FakePlayer();
      final c = AlertCenter(player: p);
      expect(c.current, isNull);
      c.show(AlertKind.reply, 'K1ABC respondeu!', 'PY2XYZ K1ABC -08');
      expect(c.current!.title, 'K1ABC respondeu!');
      expect(c.flashTick, 1);
      expect(p.played, [AlertKind.reply]);
      expect(p.vibrated, [AlertKind.reply]);
      c.dispose();
    });

    test('respeita as opções de som e vibração', () {
      final p = FakePlayer();
      final c = AlertCenter(player: p)
        ..soundEnabled = false
        ..vibrateEnabled = false;
      c.show(AlertKind.txStart, 'Transmitindo');
      expect(p.played, isEmpty);
      expect(p.vibrated, isEmpty);
      expect(c.current, isNotNull); // o aviso visual continua
      c.dispose();
    });

    test('some sozinho após o tempo configurado e fecha ao tocar', () async {
      final c = AlertCenter(player: FakePlayer(), autoDismiss: const Duration(milliseconds: 40));
      c.show(AlertKind.info, 'oi');
      expect(c.current, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(c.current, isNull);
      c.show(AlertKind.info, 'de novo');
      c.dismiss();
      expect(c.current, isNull);
      c.dispose();
    });

    test('histórico limitado a 50', () {
      final c = AlertCenter(player: FakePlayer());
      for (var i = 0; i < 60; i++) {
        c.show(AlertKind.info, 'a$i');
      }
      expect(c.history.length, 50);
      expect(c.history.last.title, 'a59');
      c.dispose();
    });
  });
}
