import 'package:flutter_test/flutter_test.dart';
import 'package:jtmobile/core/modes.dart';

void main() {
  group('Catálogo de modos', () {
    test('FT8 e FT4 estão implementados com codec; os demais ainda não', () {
      expect(modeById('FT8').implemented, isTrue);
      expect(modeById('FT8').ftx, isNotNull);
      expect(modeById('FT4').implemented, isTrue);
      for (final id in ['JT65', 'JT9', 'FST4', 'WSPR']) {
        expect(modeById(id).implemented, isFalse, reason: id);
        expect(modeById(id).ftx, isNull, reason: id);
      }
    });

    test('ids são únicos e modeById cai em FT8 se desconhecido', () {
      expect(kModes.map((m) => m.id).toSet().length, kModes.length);
      expect(modeById('XYZ').id, 'FT8');
    });

    test('parâmetros de tempo coerentes', () {
      for (final m in kModes) {
        expect(m.decodeAtSeconds, lessThan(m.slotSeconds), reason: m.id);
        expect(m.txStartOffset, lessThan(m.slotSeconds / 2), reason: m.id);
      }
      expect(modeById('FT8').slotSeconds, 15);
      expect(modeById('FT4').slotSeconds, 7.5);
      expect(modeById('JT65').slotSeconds, 60);
    });
  });

  group('Bandas', () {
    test('frequências de dial padrão', () {
      final b20 = kBands[bandIndexOf(14074000)];
      expect(b20.name, '20m');
      expect(b20.dialFor('FT8'), 14074000);
      expect(b20.dialFor('FT4'), 14080000);
      expect(b20.dialFor('JT65'), 14076000);
      expect(b20.dialFor('WSPR'), isNull);
    });

    test('bandIndexOf identifica a banda ou devolve -1', () {
      expect(kBands[bandIndexOf(7074000)].name, '40m');
      expect(kBands[bandIndexOf(50313000)].name, '6m');
      expect(bandIndexOf(12000000), -1);
    });

    test('toda frequência de dial está dentro da sua banda', () {
      for (final b in kBands) {
        for (final e in b.dial.entries) {
          expect(b.contains(e.value), isTrue, reason: '${b.name} ${e.key}');
        }
      }
    });
  });
}
