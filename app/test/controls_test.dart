// Testes dos controles do operador: travar etapa (reenviar uma etapa específica) e opções de alerta.
import 'package:flutter_test/flutter_test.dart';
import 'package:jtmobile/core/models.dart';
import 'package:jtmobile/engine/alerts.dart';
import 'package:jtmobile/engine/qso.dart';
import 'package:jtmobile/engine/sim_script.dart';

const me = 'PY2XYZ';

Decode dec(String msg, {double snr = -5}) => Decode(
      slotStart: DateTime.utc(2026, 1, 1, 12),
      snr: snr,
      dt: 0.0,
      freq: 1000,
      message: msg,
      myCall: me,
      myGrid: 'GG66',
    );

class _P implements AlertPlayer {
  final played = <AlertKind>[];
  @override
  Future<void> play(AlertKind kind) async => played.add(kind);
  @override
  Future<void> vibrate(AlertKind kind) async {}
}

void main() {
  group('Travar etapa (reenviar uma etapa específica)', () {
    test('sem trava, a resposta da outra estação avança a etapa', () {
      final q = QsoManager(myCall: me, myGrid: 'GG66');
      q.startWith(dec('CQ K1ABC FN42', snr: -3), slotParity: 0);
      expect(q.txIndex, 1);
      q.onDecode(dec('PY2XYZ K1ABC -08'), slotParity: 1);
      expect(q.txIndex, 3, reason: 'recebeu o relatório: agora envia o R-relatório');
    });

    test('com a etapa travada, a mensagem escolhida continua sendo repetida', () {
      final q = QsoManager(myCall: me, myGrid: 'GG66');
      q.startWith(dec('CQ K1ABC FN42', snr: -3), slotParity: 0);
      q.lockStep = true;
      q.txIndex = 2; // o operador escolheu reenviar o relatório (Tx2)
      final ev = q.onDecode(dec('PY2XYZ K1ABC -08'), slotParity: 1);
      expect(ev, QsoEvent.none);
      expect(q.txIndex, 2, reason: 'travado: não avança');
      expect(q.rptRcvd, '-08', reason: 'mas o relatório recebido é registrado');
      expect(q.currentMessage, startsWith('K1ABC PY2XYZ '));
      // destravando, o QSO volta a avançar
      q.lockStep = false;
      q.onDecode(dec('PY2XYZ K1ABC -08'), slotParity: 1);
      expect(q.txIndex, 3);
    });

    test('a trava não impede o encerramento do QSO (RR73/73) e é zerada ao limpar', () {
      final q = QsoManager(myCall: me, myGrid: 'GG66');
      q.startWith(dec('CQ K1ABC FN42'), slotParity: 0);
      q.lockStep = true;
      expect(q.onDecode(dec('PY2XYZ K1ABC RR73'), slotParity: 1), QsoEvent.complete);
      q.clear();
      expect(q.lockStep, isFalse);
    });

    test('o simulador responde de novo se a mesma etapa for reenviada', () {
      final first = simReplyTo('K1ABC PY2XYZ R-03', me)!;
      final again = simReplyTo('K1ABC PY2XYZ R-03', me)!;
      expect(first.text, again.text);
      expect(first.text, 'PY2XYZ K1ABC RR73');
    });
  });

  group('Opções de alerta', () {
    test('com a faixa desligada não há pop-up, mas o som e a borda continuam', () {
      final p = _P();
      final c = AlertCenter(player: p)..bannerEnabled = false;
      c.show(AlertKind.reply, 'K1ABC respondeu!');
      expect(c.current, isNull, reason: 'sem faixa no topo');
      expect(p.played, [AlertKind.reply], reason: 'som mantido');
      expect(c.flashTick, 1, reason: 'a borda ainda pode piscar (flashEnabled)');
      c.dispose();
    });

    test('flashEnabled e bannerEnabled são independentes', () {
      final c = AlertCenter(player: _P())..flashEnabled = false;
      c.show(AlertKind.info, 'x');
      expect(c.current, isNotNull);
      expect(c.flashEnabled, isFalse);
      c.dispose();
    });
  });
}
