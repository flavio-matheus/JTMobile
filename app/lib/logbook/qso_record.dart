/// Modelo de um contato (QSO) do logbook, mapeado para/de campos ADIF padrão.
library;

import 'adif.dart';

/// Serviços de logbook online previstos (integrações da fase 2 — veja `docs/LOGBOOK.md`).
/// O estado de envio de cada serviço é guardado nos campos ADIF padrão correspondentes,
/// de modo que o log local já nasce compatível com as integrações futuras.
enum LogService {
  /// QRZ.com Logbook — campo `QRZCOM_QSO_UPLOAD_STATUS` (Y/N/M).
  qrz('QRZ.com', 'QRZCOM_QSO_UPLOAD_STATUS'),

  /// Logbook of The World (ARRL) — campo `LOTW_QSL_SENT` (Y/N/R/Q). Exige assinatura via TQSL.
  lotw('LoTW', 'LOTW_QSL_SENT'),

  /// eQSL.cc — campo `EQSL_QSL_SENT`.
  eqsl('eQSL', 'EQSL_QSL_SENT'),

  /// Club Log — campo `CLUBLOG_QSO_UPLOAD_STATUS`.
  clublog('Club Log', 'CLUBLOG_QSO_UPLOAD_STATUS'),

  /// HRDLog.net — campo `HRDLOG_QSO_UPLOAD_STATUS`.
  hrdlog('HRDLog', 'HRDLOG_QSO_UPLOAD_STATUS');

  const LogService(this.label, this.adifField);

  /// Nome exibido.
  final String label;

  /// Campo ADIF que guarda o status de envio.
  final String adifField;
}

/// Um QSO. Imutável por convenção: use [copyWith] para editar.
class QsoRecord {
  QsoRecord({
    String? id,
    required this.call,
    this.grid = '',
    this.name = '',
    this.comment = '',
    required this.timeOn,
    DateTime? timeOff,
    required this.freqHz,
    required this.mode,
    this.rstSent = '',
    this.rstRcvd = '',
    this.myCall = '',
    this.myGrid = '',
    this.txPowerW,
    Map<String, String>? extra,
  })  : timeOff = timeOff ?? timeOn,
        extra = extra ?? <String, String>{},
        id = id ?? '${timeOn.millisecondsSinceEpoch}-${call.toUpperCase()}';

  /// Identificador estável (hora de início + indicativo).
  final String id;

  /// Indicativo do contato.
  final String call;

  /// Locator (Maidenhead) do contato.
  final String grid;

  /// Nome do operador.
  final String name;

  /// Comentário livre.
  final String comment;

  /// Início e fim do QSO (UTC).
  final DateTime timeOn;
  final DateTime timeOff;

  /// Frequência em Hz.
  final int freqHz;

  /// Id do modo ("FT8", "FT4", "JT65"...).
  final String mode;

  /// Relatórios enviado/recebido (ex.: "-12").
  final String rstSent;
  final String rstRcvd;

  /// Minha estação.
  final String myCall;
  final String myGrid;

  /// Potência de transmissão (W), se informada.
  final double? txPowerW;

  /// Campos ADIF adicionais/desconhecidos preservados na importação/exportação
  /// (inclui os status de envio aos serviços, veja [LogService]).
  final Map<String, String> extra;

  /// Banda ADIF (ex.: "20m") derivada da frequência; vazio se fora das bandas conhecidas.
  String get band => bandOfFrequency(freqHz);

  /// Status de envio ao [service] ("Y", "N", "M"...), ou "N" se nunca enviado.
  String uploadStatus(LogService service) => extra[service.adifField] ?? 'N';

  QsoRecord copyWith({
    String? call,
    String? grid,
    String? name,
    String? comment,
    DateTime? timeOn,
    DateTime? timeOff,
    int? freqHz,
    String? mode,
    String? rstSent,
    String? rstRcvd,
    String? myCall,
    String? myGrid,
    double? txPowerW,
    Map<String, String>? extra,
  }) =>
      QsoRecord(
        id: id,
        call: call ?? this.call,
        grid: grid ?? this.grid,
        name: name ?? this.name,
        comment: comment ?? this.comment,
        timeOn: timeOn ?? this.timeOn,
        timeOff: timeOff ?? this.timeOff,
        freqHz: freqHz ?? this.freqHz,
        mode: mode ?? this.mode,
        rstSent: rstSent ?? this.rstSent,
        rstRcvd: rstRcvd ?? this.rstRcvd,
        myCall: myCall ?? this.myCall,
        myGrid: myGrid ?? this.myGrid,
        txPowerW: txPowerW ?? this.txPowerW,
        extra: extra ?? Map<String, String>.of(this.extra),
      );

  static String _d(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}';
  static String _t(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}${t.second.toString().padLeft(2, '0')}';

  /// Converte para um registro ADIF (campos padrão + [extra]).
  AdifRecord toAdif() {
    final m = <String, String>{
      'CALL': call,
      'QSO_DATE': _d(timeOn),
      'TIME_ON': _t(timeOn),
      'QSO_DATE_OFF': _d(timeOff),
      'TIME_OFF': _t(timeOff),
      'BAND': band,
      'FREQ': (freqHz / 1e6).toStringAsFixed(6),
    };
    // FT4 é MFSK/FT4 em ADIF; os demais modos usam o próprio nome.
    if (mode == 'FT4') {
      m['MODE'] = 'MFSK';
      m['SUBMODE'] = 'FT4';
    } else {
      m['MODE'] = mode;
    }
    if (rstSent.isNotEmpty) m['RST_SENT'] = rstSent;
    if (rstRcvd.isNotEmpty) m['RST_RCVD'] = rstRcvd;
    if (grid.isNotEmpty) m['GRIDSQUARE'] = grid;
    if (name.isNotEmpty) m['NAME'] = name;
    if (comment.isNotEmpty) m['COMMENT'] = comment;
    if (myCall.isNotEmpty) m['STATION_CALLSIGN'] = myCall;
    if (myGrid.isNotEmpty) m['MY_GRIDSQUARE'] = myGrid;
    if (txPowerW != null) m['TX_PWR'] = txPowerW!.toStringAsFixed(txPowerW! == txPowerW!.roundToDouble() ? 0 : 1);
    for (final e in extra.entries) {
      m.putIfAbsent(e.key, () => e.value);
    }
    return m;
  }

  /// Cria um [QsoRecord] a partir de um registro ADIF. Retorna `null` se faltar CALL/data/hora.
  static QsoRecord? fromAdif(AdifRecord r) {
    final call = r['CALL'];
    final date = r['QSO_DATE'];
    if (call == null || call.isEmpty || date == null || date.length < 8) return null;
    DateTime? parse(String? d, String? t) {
      if (d == null || d.length < 8) return null;
      final tt = (t ?? '000000').padRight(6, '0');
      return DateTime.utc(int.parse(d.substring(0, 4)), int.parse(d.substring(4, 6)), int.parse(d.substring(6, 8)),
          int.parse(tt.substring(0, 2)), int.parse(tt.substring(2, 4)), int.parse(tt.substring(4, 6)));
    }

    try {
      final on = parse(date, r['TIME_ON'])!;
      final off = parse(r['QSO_DATE_OFF'] ?? date, r['TIME_OFF'] ?? r['TIME_ON']) ?? on;
      var mode = (r['MODE'] ?? '').toUpperCase();
      final sub = (r['SUBMODE'] ?? '').toUpperCase();
      if (mode == 'MFSK' && sub.isNotEmpty) mode = sub;
      final mhz = double.tryParse(r['FREQ'] ?? '') ?? 0;
      const known = {
        'CALL', 'QSO_DATE', 'TIME_ON', 'QSO_DATE_OFF', 'TIME_OFF', 'BAND', 'FREQ', 'MODE', 'SUBMODE',
        'RST_SENT', 'RST_RCVD', 'GRIDSQUARE', 'NAME', 'COMMENT', 'STATION_CALLSIGN', 'MY_GRIDSQUARE', 'TX_PWR',
      };
      final extra = <String, String>{
        for (final e in r.entries)
          if (!known.contains(e.key)) e.key: e.value,
      };
      return QsoRecord(
        call: call.toUpperCase(),
        grid: (r['GRIDSQUARE'] ?? '').toUpperCase(),
        name: r['NAME'] ?? '',
        comment: r['COMMENT'] ?? '',
        timeOn: on,
        timeOff: off,
        freqHz: (mhz * 1e6).round(),
        mode: mode,
        rstSent: r['RST_SENT'] ?? '',
        rstRcvd: r['RST_RCVD'] ?? '',
        myCall: r['STATION_CALLSIGN'] ?? '',
        myGrid: r['MY_GRIDSQUARE'] ?? '',
        txPowerW: double.tryParse(r['TX_PWR'] ?? ''),
        extra: extra,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Banda ADIF ("20m") para uma frequência em Hz; "" se desconhecida.
String bandOfFrequency(int hz) {
  final m = hz / 1e6;
  const edges = <(double, double, String)>[
    (1.8, 2.0, '160m'),
    (3.5, 4.0, '80m'),
    (5.06, 5.5, '60m'),
    (7.0, 7.3, '40m'),
    (10.1, 10.15, '30m'),
    (14.0, 14.35, '20m'),
    (18.068, 18.168, '17m'),
    (21.0, 21.45, '15m'),
    (24.89, 24.99, '12m'),
    (28.0, 29.7, '10m'),
    (50.0, 54.0, '6m'),
    (144.0, 148.0, '2m'),
    (430.0, 450.0, '70cm'),
  ];
  for (final e in edges) {
    if (m >= e.$1 && m <= e.$2) return e.$3;
  }
  return '';
}
