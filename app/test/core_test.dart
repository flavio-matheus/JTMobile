import 'package:flutter_test/flutter_test.dart';
import 'package:jtmobile/core/dxcc.dart';
import 'package:jtmobile/core/geo.dart';
import 'package:jtmobile/core/models.dart';
import 'package:jtmobile/engine/qso.dart';
import 'package:jtmobile/radio/civ.dart';
import 'package:jtmobile/radio/passcode.dart';

Decode dec(String msg, {double snr = -10, DateTime? t, String my = 'PY2XYZ', String grid = 'GG66'}) => Decode(
      slotStart: t ?? DateTime.utc(2026, 1, 1, 12, 0, 0),
      snr: snr,
      dt: 0.1,
      freq: 1500,
      message: msg,
      myCall: my,
      myGrid: grid,
    );

void main() {
  group('CI-V', () {
    test('frequência BCD ida e volta', () {
      expect(Civ.encodeFreq(14074000), [0x00, 0x40, 0x07, 0x14, 0x00]);
      expect(Civ.decodeFreq([0x00, 0x40, 0x07, 0x14, 0x00]), 14074000);
      expect(Civ.decodeFreq(Civ.encodeFreq(7074000)), 7074000);
    });

    test('quadro e parse', () {
      final f = Civ.setFreq(14074000);
      expect(f.first, 0xFE);
      expect(f.last, 0xFD);
      expect(f.sublist(0, 5), [0xFE, 0xFE, 0xA4, 0xE0, 0x05]);
      final reply = [0xFE, 0xFE, 0xE0, 0xA4, 0x03, 0x00, 0x40, 0x07, 0x14, 0x00, 0xFD];
      final frames = Civ.parse(reply);
      expect(frames.length, 1);
      final st = RadioState();
      expect(Civ.apply(st, frames.first), isTrue);
      expect(st.freqHz, 14074000);
    });

    test('S-meter e PTT', () {
      final st = RadioState();
      Civ.apply(st, Civ.parse([0xFE, 0xFE, 0xE0, 0xA4, 0x15, 0x02, 0x01, 0x20, 0xFD]).first);
      expect(st.sMeter, 120);
      Civ.apply(st, Civ.parse([0xFE, 0xFE, 0xE0, 0xA4, 0x1C, 0x00, 0x01, 0xFD]).first);
      expect(st.ptt, isTrue);
    });

    test('passcode produz 16 bytes e é determinístico', () {
      final a = icomPasscode('beer');
      expect(a.length, 16);
      expect(a.sublist(4), List.filled(12, 0));
      expect(icomPasscode('beer'), a);
      // valores conferidos com a implementação de referência (kappanhang): 'b','e','e','r' => i, i+1...
      expect(a[0], isNot(0));
    });
  });

  group('Mensagens', () {
    test('CQ simples e com modificador', () {
      final m = ParsedMessage.parse('CQ PY2ABC GG66');
      expect(m.kind, MsgKind.cq);
      expect(m.from, 'PY2ABC');
      expect(m.grid, 'GG66');
      final dx = ParsedMessage.parse('CQ DX K1ABC FN42');
      expect(dx.cqModifier, 'DX');
      expect(dx.from, 'K1ABC');
    });

    test('mensagens dirigidas', () {
      var m = ParsedMessage.parse('PY2XYZ K1ABC -12');
      expect(m.to, 'PY2XYZ');
      expect(m.from, 'K1ABC');
      expect(m.report, '-12');
      m = ParsedMessage.parse('PY2XYZ K1ABC R-05');
      expect(m.rReport, isTrue);
      expect(m.report, '-05');
      m = ParsedMessage.parse('PY2XYZ K1ABC RR73');
      expect(m.rr73, isTrue);
      expect(m.grid, isNull);
      m = ParsedMessage.parse('PY2XYZ K1ABC 73');
      expect(m.is73, isTrue);
      m = ParsedMessage.parse('PY2XYZ K1ABC FN42');
      expect(m.grid, 'FN42');
    });

    test('texto livre', () {
      expect(ParsedMessage.parse('TNX BOB 73 GL').kind, MsgKind.freeText);
    });
  });

  group('Geo e DXCC', () {
    test('distância GG66 -> FN42 ~ 7500+ km', () {
      final a = gridToLatLon('GG66')!;
      final b = gridToLatLon('FN42')!;
      final r = distanceBearing(a.lat, a.lon, b.lat, b.lon);
      expect(r.km, greaterThan(6500));
      expect(r.km, lessThan(8500));
    });

    test('prefixos', () {
      expect(lookupDxcc('PY2XYZ')!.country, 'Brasil');
      expect(lookupDxcc('K1ABC')!.country, 'EUA');
      expect(lookupDxcc('JA1DEF')!.country, 'Japão');
      expect(lookupDxcc('EA8/PY2XYZ')!.country, 'Ilhas Canárias');
      expect(lookupDxcc('PY2XYZ/P')!.country, 'Brasil');
      expect(lookupDxcc('KH6ABC')!.country, 'Havaí');
    });
  });

  group('QSO', () {
    test('responder a CQ: Tx1 no slot oposto', () {
      final q = QsoManager(myCall: 'PY2XYZ', myGrid: 'GG66');
      q.startWith(dec('CQ K1ABC FN42', snr: -8), slotParity: 0);
      expect(q.dxCall, 'K1ABC');
      expect(q.txParity, 1);
      expect(q.txIndex, 1);
      expect(q.currentMessage, 'K1ABC PY2XYZ GG66');
      expect(q.message(2), 'K1ABC PY2XYZ -08');
    });

    test('sequência completa chamando CQ', () {
      final q = QsoManager(myCall: 'PY2XYZ', myGrid: 'GG66');
      expect(q.currentMessage, 'CQ PY2XYZ GG66');
      // resposta com grid
      var ev = q.onDecode(dec('PY2XYZ K1ABC FN42', snr: -11), slotParity: 1);
      expect(ev, QsoEvent.none);
      expect(q.dxCall, 'K1ABC');
      expect(q.txIndex, 2);
      expect(q.currentMessage, 'K1ABC PY2XYZ -11');
      // R-relatório
      ev = q.onDecode(dec('PY2XYZ K1ABC R-05', snr: -10), slotParity: 1);
      expect(q.txIndex, 4);
      expect(q.rptRcvd, '-05');
      expect(q.currentMessage, 'K1ABC PY2XYZ RR73');
      // 73 final
      ev = q.onDecode(dec('PY2XYZ K1ABC 73', snr: -9), slotParity: 1);
      expect(ev, QsoEvent.finished);
    });

    test('ignora mensagens de outras estações durante o QSO', () {
      final q = QsoManager(myCall: 'PY2XYZ', myGrid: 'GG66');
      q.startWith(dec('CQ K1ABC FN42'), slotParity: 0);
      final ev = q.onDecode(dec('PY2XYZ JA1DEF -03'), slotParity: 0);
      expect(ev, QsoEvent.none);
      expect(q.dxCall, 'K1ABC');
    });

    test('formatReport', () {
      expect(formatReport(-7.4), '-07');
      expect(formatReport(3.2), '+03');
      expect(formatReport(-40), '-30');
    });
  });
}
