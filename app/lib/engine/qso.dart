/// Sequenciador de QSO no estilo WSJT-X/JTDX.
///
/// Mensagens: Tx1 (grid), Tx2 (relatório), Tx3 (R+relatório), Tx4 (RR73), Tx5 (73), Tx6 (CQ).
/// Com a auto-sequência ligada, cada mensagem recebida da estação em contato faz o sequenciador
/// avançar para a próxima mensagem a transmitir. É lógica pura, coberta por `test/core_test.dart`.
library;

import '../core/dxcc.dart';
import '../core/models.dart';

String formatReport(double snr) {
  final n = snr.round().clamp(-30, 50);
  return '${n < 0 ? '-' : '+'}${n.abs().toString().padLeft(2, '0')}';
}

/// Resultado de processar uma mensagem recebida.
///  * [none]: o QSO continua (a próxima mensagem a transmitir pode ter mudado);
///  * [complete]: recebemos RR73/RRR — o QSO está **completo para registro**, mas ainda devemos
///    transmitir o 73 final (Tx5);
///  * [finished]: recebemos 73 — o QSO terminou e **não há mais nada a transmitir**.
enum QsoEvent { none, complete, finished }

/// Sequenciador de QSO no estilo WSJT-X/JTDX (mensagens Tx1..Tx6 e auto-sequência).
class QsoManager {
  QsoManager({required this.myCall, required this.myGrid, this.cqText = 'CQ'});

  String myCall;
  String myGrid;
  String cqText;

  String dxCall = '';
  String dxGrid = '';
  String rptSent = '-10';
  String rptRcvd = '';
  int txIndex = 6; // 1..6
  int? txParity; // 0 = slot par (1º), 1 = ímpar (2º); null = qualquer
  DateTime? started;
  bool completed = false;

  String message(int i) {
    final dx = dxCall;
    switch (i) {
      case 1:
        return '$dx $myCall ${_grid4()}'.trim();
      case 2:
        return '$dx $myCall $rptSent'.trim();
      case 3:
        return '$dx $myCall R$rptSent'.trim();
      case 4:
        return '$dx $myCall RR73'.trim();
      case 5:
        return '$dx $myCall 73'.trim();
      case 6:
      default:
        return '$cqText $myCall ${_grid4()}'.trim();
    }
  }

  String _grid4() => myGrid.length >= 4 ? myGrid.substring(0, 4).toUpperCase() : '';

  String get currentMessage => (txIndex != 6 && dxCall.isEmpty) ? message(6) : message(txIndex);

  /// Reinicia para modo CQ.
  void clear() {
    dxCall = '';
    dxGrid = '';
    rptRcvd = '';
    rptSent = '-10';
    txIndex = 6;
    txParity = null;
    started = null;
    completed = false;
  }

  /// Inicia um QSO respondendo a [d] (clique numa decodificação).
  void startWith(Decode d, {required int slotParity}) {
    final from = d.parsed.from;
    if (from == null) return;
    dxCall = from;
    dxGrid = d.parsed.grid ?? '';
    rptSent = formatReport(d.snr);
    rptRcvd = '';
    completed = false;
    started = DateTime.now().toUtc();
    txParity = 1 - slotParity; // transmite no slot oposto ao dele
    if (d.toMe) {
      // Ele está me chamando: continua a sequência a partir da mensagem recebida.
      txIndex = 2;
      _advance(d);
    } else {
      txIndex = 1;
    }
  }

  /// Processa uma mensagem recebida (modo auto-sequência). Retorna true se o estado de TX mudou.
  QsoEvent onDecode(Decode d, {required int slotParity}) {
    if (!d.toMe) return QsoEvent.none;
    final from = d.parsed.from;
    if (from == null) return QsoEvent.none;
    final calling = txIndex == 6 || dxCall.isEmpty;
    if (!calling && baseCall(from) != baseCall(dxCall)) return QsoEvent.none;

    if (calling) {
      // Alguém respondeu ao meu CQ.
      dxCall = from;
      dxGrid = d.parsed.grid ?? '';
      rptSent = formatReport(d.snr);
      rptRcvd = '';
      completed = false;
      started = DateTime.now().toUtc();
      txParity = 1 - slotParity;
      txIndex = 2;
    } else {
      rptSent = formatReport(d.snr);
    }
    return _advance(d);
  }

  QsoEvent _advance(Decode d) {
    final p = d.parsed;
    if (p.is73) {
      // A outra estação encerrou: registra e não responde (evita "73" duplicado).
      completed = true;
      return QsoEvent.finished;
    }
    if (p.rr73 || p.rrr) {
      txIndex = 5;
      completed = true;
      return QsoEvent.complete;
    }
    if (p.rReport && p.report != null) {
      rptRcvd = p.report!;
      txIndex = 4;
      return QsoEvent.none;
    }
    if (p.report != null) {
      rptRcvd = p.report!;
      txIndex = 3;
      return QsoEvent.none;
    }
    if (p.grid != null) {
      dxGrid = p.grid!;
      txIndex = 2;
    }
    return QsoEvent.none;
  }
}
