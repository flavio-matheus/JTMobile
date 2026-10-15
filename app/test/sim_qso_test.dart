// Teste de ponta a ponta (lógica) do simulador: o QsoManager do app conversando com as estações
// simuladas (simReplyTo), sem áudio nem relógio. Garante que os dois roteiros de QSO completam.
import 'package:flutter_test/flutter_test.dart';
import 'package:jtmobile/core/models.dart';
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

/// Executa o ciclo: transmite a mensagem atual -> o simulador responde -> o QsoManager processa.
/// Devolve a lista de mensagens transmitidas pelo usuário e o último evento.
({List<String> sent, List<String> replies, QsoEvent last}) runQso(QsoManager q, {int maxCycles = 12}) {
  final sent = <String>[];
  final replies = <String>[];
  var last = QsoEvent.none;
  var cq = 0;
  for (var i = 0; i < maxCycles; i++) {
    final tx = q.currentMessage;
    sent.add(tx);
    final r = simReplyTo(tx, me, cqCounter: cq);
    if (tx.startsWith('CQ')) cq++;
    if (r == null) break;
    replies.add(r.text);
    last = q.onDecode(dec(r.text, snr: r.station.snr), slotParity: 1);
    if (last == QsoEvent.finished) break;
  }
  return (sent: sent, replies: replies, last: last);
}

void main() {
  test('Roteiro A: você responde a um CQ -> completa com RR73 e envia o 73 final', () {
    final q = QsoManager(myCall: me, myGrid: 'GG66');
    q.startWith(dec('CQ K1ABC FN42', snr: -3), slotParity: 0);
    final r = runQso(q);
    expect(r.sent, ['K1ABC PY2XYZ GG66', 'K1ABC PY2XYZ R-03', 'K1ABC PY2XYZ 73']);
    expect(r.replies, ['PY2XYZ K1ABC -08', 'PY2XYZ K1ABC RR73']);
    expect(q.completed, isTrue);
    expect(q.rptRcvd, '-08');
  });

  test('Roteiro B: você chama CQ -> a estação responde e o QSO termina com o 73 dela', () {
    final q = QsoManager(myCall: me, myGrid: 'GG66');
    expect(q.currentMessage, 'CQ PY2XYZ GG66');
    final r = runQso(q);
    expect(r.sent.first, 'CQ PY2XYZ GG66');
    expect(r.replies.first, 'PY2XYZ K1ABC FN42');
    expect(r.sent[1], startsWith('K1ABC PY2XYZ '));
    expect(r.replies.last, 'PY2XYZ K1ABC 73');
    expect(r.last, QsoEvent.finished);
    expect(r.sent.last, 'K1ABC PY2XYZ RR73');
    expect(q.dxCall, 'K1ABC');
  });

  test('CQ repetidos alternam a estação que responde', () {
    final a = simReplyTo('CQ PY2XYZ GG66', me, cqCounter: 0)!;
    final b = simReplyTo('CQ PY2XYZ GG66', me, cqCounter: 1)!;
    expect(a.station.call, isNot(b.station.call));
  });

  test('Sem resposta: estação inexistente, 73 do usuário e mensagens alheias', () {
    expect(simReplyTo('XX9XX PY2XYZ GG66', me), isNull);
    expect(simReplyTo('K1ABC PY2XYZ 73', me), isNull);
    expect(simReplyTo('K1ABC JA1DEF -10', me), isNull); // não é uma mensagem minha
    expect(simReplyTo('K1ABC PY2XYZ GG66', ''), isNull);
  });

  test('As estações "alwaysCq" existem e têm sinal forte', () {
    final cqs = kSimStations.where((s) => s.alwaysCq).toList();
    expect(cqs.length, greaterThanOrEqualTo(2));
    for (final s in cqs) {
      expect(s.snr, greaterThan(-10));
    }
  });
}
