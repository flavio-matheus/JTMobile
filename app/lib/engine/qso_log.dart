import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class QsoRecord {
  QsoRecord({
    required this.call,
    required this.grid,
    required this.time,
    required this.freqHz,
    required this.mode,
    required this.rstSent,
    required this.rstRcvd,
    required this.myCall,
    required this.myGrid,
  });

  final String call;
  final String grid;
  final DateTime time; // UTC
  final int freqHz;
  final String mode; // FT8 / FT4
  final String rstSent;
  final String rstRcvd;
  final String myCall;
  final String myGrid;

  static String _f(String tag, String v) => v.isEmpty ? '' : '<$tag:${v.length}>$v ';

  String toAdif() {
    final d = '${time.year.toString().padLeft(4, '0')}${time.month.toString().padLeft(2, '0')}${time.day.toString().padLeft(2, '0')}';
    final t = '${time.hour.toString().padLeft(2, '0')}${time.minute.toString().padLeft(2, '0')}${time.second.toString().padLeft(2, '0')}';
    final mhz = (freqHz / 1e6).toStringAsFixed(6);
    final band = _bandOf(freqHz);
    final sb = StringBuffer()
      ..write(_f('CALL', call))
      ..write(_f('QSO_DATE', d))
      ..write(_f('TIME_ON', t))
      ..write(_f('BAND', band))
      ..write(_f('FREQ', mhz))
      ..write(mode == 'FT4' ? _f('MODE', 'MFSK') + _f('SUBMODE', 'FT4') : _f('MODE', 'FT8'))
      ..write(_f('RST_SENT', rstSent))
      ..write(_f('RST_RCVD', rstRcvd))
      ..write(_f('GRIDSQUARE', grid))
      ..write(_f('STATION_CALLSIGN', myCall))
      ..write(_f('MY_GRIDSQUARE', myGrid))
      ..write('<EOR>\n');
    return sb.toString();
  }

  static String _bandOf(int hz) {
    final m = hz / 1e6;
    const edges = <(double, double, String)>[
      (1.8, 2.0, '160m'),
      (3.5, 4.0, '80m'),
      (5.3, 5.5, '60m'),
      (7.0, 7.3, '40m'),
      (10.1, 10.15, '30m'),
      (14.0, 14.35, '20m'),
      (18.068, 18.168, '17m'),
      (21.0, 21.45, '15m'),
      (24.89, 24.99, '12m'),
      (28.0, 29.7, '10m'),
      (50.0, 54.0, '6m'),
    ];
    for (final e in edges) {
      if (m >= e.$1 && m <= e.$2) return e.$3;
    }
    return '';
  }
}

/// Registro de QSOs em memória, gravado em ADIF (`ft_mobile.adi`) na pasta de documentos do app.
class QsoLog extends ChangeNotifier {
  final List<QsoRecord> records = [];

  void add(QsoRecord r) {
    records.add(r);
    notifyListeners();
    _append(r);
  }

  Future<File?> file() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/ft_mobile.adi');
    } catch (_) {
      return null;
    }
  }

  Future<void> _append(QsoRecord r) async {
    final f = await file();
    if (f == null) return;
    if (!await f.exists()) {
      await f.writeAsString('FT Mobile ADIF export\n<ADIF_VER:5>3.1.4\n<PROGRAMID:9>FT Mobile\n<EOH>\n');
    }
    await f.writeAsString(r.toAdif(), mode: FileMode.append);
  }
}
