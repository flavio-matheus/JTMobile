import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jtmobile/logbook/adif.dart';
import 'package:jtmobile/logbook/qso_log.dart';
import 'package:jtmobile/logbook/qso_record.dart';

QsoRecord rec(String call, {int min = 0, String mode = 'FT8', int hz = 14074500, String name = ''}) => QsoRecord(
      call: call,
      grid: 'FN42',
      name: name,
      timeOn: DateTime.utc(2026, 3, 1, 12, min, 30),
      freqHz: hz,
      mode: mode,
      rstSent: '-10',
      rstRcvd: '+02',
      myCall: 'PY2XYZ',
      myGrid: 'GG66',
    );

void main() {
  group('ADIF', () {
    test('serializa e interpreta (ida e volta)', () {
      final text = Adif.header() + Adif.serialize(rec('K1ABC').toAdif()) + Adif.serialize(rec('JA1DEF', min: 5).toAdif());
      final parsed = Adif.parse(text);
      expect(parsed.length, 2);
      expect(parsed[0]['CALL'], 'K1ABC');
      expect(parsed[0]['BAND'], '20m');
      expect(parsed[0]['MODE'], 'FT8');
      expect(parsed[1]['CALL'], 'JA1DEF');
    });

    test('tamanhos de campo são em bytes UTF-8', () {
      final f = Adif.field('NAME', 'José');
      expect(f, startsWith('<NAME:5>')); // "é" ocupa 2 bytes
      final r = Adif.parse('<EOH><CALL:5>K1ABC<NAME:5>José <QSO_DATE:8>20260301<EOR>').first;
      expect(r['NAME'], 'José');
    });

    test('ignora o cabeçalho e aceita minúsculas', () {
      final r = Adif.parse('cabecalho <ADIF_VER:5>3.1.4 <eoh>\n<call:5>K1ABC <qso_date:8>20260301 <eor>');
      expect(r.length, 1);
      expect(r.first['CALL'], 'K1ABC');
    });
  });

  group('QsoRecord', () {
    test('FT4 vira MFSK/FT4 no ADIF e volta a FT4', () {
      final a = rec('K1ABC', mode: 'FT4').toAdif();
      expect(a['MODE'], 'MFSK');
      expect(a['SUBMODE'], 'FT4');
      expect(QsoRecord.fromAdif(a)!.mode, 'FT4');
    });

    test('campos desconhecidos e status de serviços são preservados', () {
      final a = rec('K1ABC').toAdif();
      a['QRZCOM_QSO_UPLOAD_STATUS'] = 'Y';
      a['APP_X_FOO'] = 'bar';
      final r = QsoRecord.fromAdif(a)!;
      expect(r.uploadStatus(LogService.qrz), 'Y');
      expect(r.uploadStatus(LogService.lotw), 'N');
      expect(r.toAdif()['APP_X_FOO'], 'bar');
    });

    test('bandOfFrequency', () {
      expect(bandOfFrequency(14074000), '20m');
      expect(bandOfFrequency(7047500), '40m');
      expect(bandOfFrequency(9000000), '');
    });
  });

  group('QsoLog (persistência)', () {
    late Directory dir;
    late QsoLog log;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('jtm_log_');
      log = QsoLog(dirProvider: () async => dir);
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('grava, recarrega, edita e remove', () async {
      await log.add(rec('K1ABC'));
      await log.add(rec('JA1DEF', min: 3));
      final log2 = QsoLog(dirProvider: () async => dir);
      await log2.load();
      expect(log2.records.map((r) => r.call), ['K1ABC', 'JA1DEF']);

      await log2.update(log2.records.first.copyWith(name: 'Bob'));
      final log3 = QsoLog(dirProvider: () async => dir);
      await log3.load();
      expect(log3.records.first.name, 'Bob');

      await log3.remove(log3.records.first.id);
      final log4 = QsoLog(dirProvider: () async => dir);
      await log4.load();
      expect(log4.records.map((r) => r.call), ['JA1DEF']);
    });

    test('dupe check, países e busca', () async {
      await log.add(rec('K1ABC', name: 'Bob'));
      expect(log.isWorked('K1ABC'), isTrue);
      expect(log.isWorked('K1ABC', band: '20m', mode: 'FT8'), isTrue);
      expect(log.isWorked('K1ABC', band: '40m'), isFalse);
      expect(log.isWorked('K1ABC/P'), isTrue);
      expect(log.workedCountries(), contains('EUA'));
      expect(log.search('bob').length, 1);
      expect(log.search('zzz'), isEmpty);
    });

    test('importAdif descarta duplicados', () async {
      await log.add(rec('K1ABC'));
      final text = log.exportAdif();
      expect(await log.importAdif(text), 0);
      final other = Adif.header() + Adif.serialize(rec('DL2JKL', min: 20).toAdif());
      expect(await log.importAdif(other), 1);
      expect(log.records.length, 2);
    });

    test('exportCsv tem cabeçalho e uma linha por QSO', () async {
      await log.add(rec('K1ABC'));
      final lines = log.exportCsv().trim().split('\n');
      expect(lines.length, 2);
      expect(lines.first, contains('indicativo'));
      expect(lines[1], contains('K1ABC'));
    });

    test('markUploaded grava o status do serviço no ADIF', () async {
      await log.add(rec('K1ABC'));
      await log.markUploaded(LogService.qrz, [log.records.first.id]);
      final log2 = QsoLog(dirProvider: () async => dir);
      await log2.load();
      expect(log2.records.first.uploadStatus(LogService.qrz), 'Y');
    });
  });
}
