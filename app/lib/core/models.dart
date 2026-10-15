/// Modelos de mensagens FT8/FT4: interpretação do texto ([ParsedMessage]) e uma decodificação
/// completa com dados da estação ([Decode]): país, distância, azimute, se é CQ ou dirigida a mim.
///
/// Regras de interpretação (formato padrão do FT8/FT4):
///  * `CQ [DX|POTA|...] INDICATIVO GRID`  — chamada geral;
///  * `DESTINO ORIGEM {GRID | -12 | R-12 | RRR | RR73 | 73}` — troca de QSO;
///  * qualquer outra coisa é tratada como texto livre.
library;

import 'dxcc.dart';
import 'geo.dart';

final RegExp _gridRe = RegExp(r'^[A-R]{2}[0-9]{2}([A-X]{2})?$', caseSensitive: false);
final RegExp _reportRe = RegExp(r'^[+-]\d{2}$');
final RegExp _rReportRe = RegExp(r'^R[+-]\d{2}$');
final RegExp _callRe = RegExp(r'^<\.\.\.>$|^<?[A-Z0-9]{1,3}[0-9][A-Z0-9]{0,3}[A-Z](/[A-Z0-9]{1,4})?>?$|^<?[A-Z0-9]{1,4}/[A-Z0-9]{2,6}>?$');

enum MsgKind { cq, directed, freeText }

/// Conteúdo estruturado de uma mensagem FT8/FT4.
class ParsedMessage {
  ParsedMessage({
    required this.text,
    required this.kind,
    this.to,
    this.from,
    this.grid,
    this.report,
    this.rReport = false,
    this.rr73 = false,
    this.rrr = false,
    this.is73 = false,
    this.cqModifier,
  });

  final String text;
  final MsgKind kind;
  final String? to; // destinatário (null em CQ)
  final String? from; // quem transmite
  final String? grid;
  final String? report; // "-10", "+03"
  final bool rReport; // "R-10"
  final bool rr73;
  final bool rrr;
  final bool is73;
  final String? cqModifier; // "DX", "POTA", "SA"...

  static bool looksLikeCall(String s) => s.isNotEmpty && _callRe.hasMatch(s.toUpperCase());

  static ParsedMessage parse(String raw) {
    final text = raw.trim().toUpperCase();
    final t = text.split(RegExp(r'\s+'));
    if (t.isEmpty || t.first.isEmpty) return ParsedMessage(text: text, kind: MsgKind.freeText);

    if (t.first == 'CQ' || t.first == 'QRZ') {
      String? mod;
      var i = 1;
      if (t.length > 2 && !looksLikeCall(t[1]) && looksLikeCall(t[2])) {
        mod = t[1]; // CQ DX CALL GRID / CQ POTA CALL GRID
        i = 2;
      }
      final call = i < t.length ? t[i] : null;
      final grid = (i + 1 < t.length && _gridRe.hasMatch(t[i + 1])) ? t[i + 1] : null;
      return ParsedMessage(text: text, kind: MsgKind.cq, from: call, grid: grid, cqModifier: mod);
    }

    if (t.length >= 2 && looksLikeCall(t[0]) && looksLikeCall(t[1])) {
      final extra = t.length >= 3 ? t[2] : '';
      return ParsedMessage(
        text: text,
        kind: MsgKind.directed,
        to: t[0],
        from: t[1],
        grid: _gridRe.hasMatch(extra) && extra != 'RR73' ? extra : null,
        report: _reportRe.hasMatch(extra) ? extra : (_rReportRe.hasMatch(extra) ? extra.substring(1) : null),
        rReport: _rReportRe.hasMatch(extra),
        rr73: extra == 'RR73',
        rrr: extra == 'RRR',
        is73: extra == '73',
      );
    }
    return ParsedMessage(text: text, kind: MsgKind.freeText);
  }
}

/// Uma mensagem decodificada em um slot.
class Decode {
  Decode({
    required this.slotStart,
    required this.snr,
    required this.dt,
    required this.freq,
    required this.message,
    required this.myCall,
    required this.myGrid,
  }) : parsed = ParsedMessage.parse(message) {
    final f = parsed.from;
    if (f != null) {
      dxcc = lookupDxcc(f);
    }
    final g = parsed.grid;
    final my = gridToLatLon(myGrid);
    final other = g != null ? gridToLatLon(g) : null;
    if (my != null && other != null) {
      final r = distanceBearing(my.lat, my.lon, other.lat, other.lon);
      km = r.km;
      bearing = r.bearing;
    }
  }

  final DateTime slotStart;
  final double snr;
  final double dt;
  final double freq;
  final String message;
  final String myCall;
  final String myGrid;
  final ParsedMessage parsed;
  DxccInfo? dxcc;
  double? km;
  double? bearing;

  bool get isCq => parsed.kind == MsgKind.cq;
  bool get toMe => myCall.isNotEmpty && parsed.to != null && baseCall(parsed.to!) == baseCall(myCall);
  bool get fromMe => myCall.isNotEmpty && parsed.from != null && baseCall(parsed.from!) == baseCall(myCall);
  String? get senderCall => parsed.from;
}
