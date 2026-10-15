/// Roteiro das estações do simulador: como elas "respondem" ao que o usuário transmite.
///
/// Lógica pura (sem áudio nem relógio) para que o QSO simulado seja **previsível e testável**.
/// O [SimRadio] usa [simReplyTo] ao fim de cada transmissão do usuário e coloca a resposta no
/// próximo período, exatamente como uma estação real faria.
///
/// Dois roteiros de QSO são suportados (formato padrão FT8/FT4):
///
/// **A) Você responde a um CQ** (clica em ↩ numa chamada CQ):
/// ```
///  você:  K1ABC PY2XYZ GG66     (Tx1)
///  ele:   PY2XYZ K1ABC -08      (relatório)
///  você:  K1ABC PY2XYZ R-10     (Tx3, automático)
///  ele:   PY2XYZ K1ABC RR73
///  você:  K1ABC PY2XYZ 73       (Tx5, automático)  → QSO completo
/// ```
/// **B) Você chama CQ**:
/// ```
///  você:  CQ PY2XYZ GG66        (Tx6)
///  ele:   PY2XYZ EA3XYZ JN11    (uma estação responde com o grid)
///  você:  EA3XYZ PY2XYZ -12     (Tx2, automático)
///  ele:   PY2XYZ EA3XYZ R-09
///  você:  EA3XYZ PY2XYZ RR73    (Tx4, automático)
///  ele:   PY2XYZ EA3XYZ 73      → QSO completo
/// ```
library;

/// Estação fictícia do simulador.
class SimStation {
  const SimStation(this.call, this.grid, this.freq, this.snr, {this.alwaysCq = false});

  /// Indicativo.
  final String call;

  /// Locator.
  final String grid;

  /// Frequência de áudio (Hz) em que a estação transmite (e responde).
  final double freq;

  /// SNR base (dB, referência 2500 Hz) com que é "ouvida".
  final double snr;

  /// Se `true`, chama CQ em **todos** os períodos (para sempre haver com quem falar).
  final bool alwaysCq;
}

/// Estações do simulador. As duas primeiras chamam CQ o tempo todo, com sinal forte.
const List<SimStation> kSimStations = [
  SimStation('K1ABC', 'FN42', 944, -3, alwaysCq: true),
  SimStation('EA3XYZ', 'JN11', 1210, -6, alwaysCq: true),
  SimStation('PY2SIM', 'GG66', 612, 4),
  SimStation('JA1DEF', 'PM95', 1732, -14),
  SimStation('LU5GHI', 'GF05', 2105, -8),
  SimStation('DL2JKL', 'JO62', 2480, -17),
  SimStation('ZS6MNO', 'KG44', 2760, -21),
  SimStation('VK3PQR', 'QF22', 372, -12),
];

/// Resposta de uma estação simulada.
class SimReply {
  const SimReply(this.station, this.text);
  final SimStation station;

  /// Mensagem FT8/FT4 que a estação transmitirá no próximo período.
  final String text;
}

SimStation? simStationByCall(String call) {
  for (final s in kSimStations) {
    if (s.call == call) return s;
  }
  return null;
}

final RegExp _grid = RegExp(r'^[A-R]{2}\d{2}$');
final RegExp _report = RegExp(r'^[+-]\d{2}$');
final RegExp _rReport = RegExp(r'^R[+-]\d{2}$');

/// Decide como o simulador responde à mensagem [myText] transmitida pelo usuário ([myCall]).
///
/// [cqCounter] escolhe, em rodízio, qual estação responde a um CQ do usuário.
/// Retorna `null` quando ninguém responde (ex.: após o seu 73, ou chamada a estação inexistente).
SimReply? simReplyTo(String myText, String myCall, {int cqCounter = 0}) {
  final tok = myText.trim().toUpperCase().split(RegExp(r'\s+'));
  final me = myCall.toUpperCase();
  if (tok.isEmpty || me.isEmpty) return null;

  // B) CQ do usuário: uma estação (em rodízio) responde com o próprio grid.
  if (tok.first == 'CQ') {
    final pool = kSimStations.where((s) => s.alwaysCq).toList();
    final st = pool[cqCounter % pool.length];
    return SimReply(st, '$me ${st.call} ${st.grid}');
  }

  // Mensagem dirigida: "DX ME <conteúdo>"
  if (tok.length >= 3 && tok[1] == me) {
    final st = simStationByCall(tok[0]);
    if (st == null) return null; // estação inexistente: sem resposta (como na vida real)
    final last = tok[2];
    if (last == '73') return null; // QSO encerrado
    if (last == 'RR73' || last == 'RRR') return SimReply(st, '$me ${st.call} 73');
    if (_rReport.hasMatch(last)) return SimReply(st, '$me ${st.call} RR73');
    if (_report.hasMatch(last)) return SimReply(st, '$me ${st.call} R-09');
    if (_grid.hasMatch(last)) return SimReply(st, '$me ${st.call} -08');
  }
  return null;
}
