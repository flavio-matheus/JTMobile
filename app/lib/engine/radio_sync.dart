/// Sincronização bidirecional entre o app e o rádio.
///
/// Objetivo: o app **lê** frequência, modo, DATA, filtro, potência, pré-amplificador e atenuador do
/// rádio, e o rádio **recebe** os ajustes feitos no app — mantendo os dois sempre coerentes.
///
/// ## Regras
/// * **Escritas do app** ([pushFrequency], [pushMode], [pushRfPower]...) enviam o comando CI-V e
///   abrem uma *janela de guarda* ([guard]) para aquele parâmetro. Durante a janela, leituras do
///   rádio com valor diferente do pedido são consideradas **resposta atrasada de um polling
///   anterior** e ignoradas — evita que o valor "pule de volta" logo após o usuário alterar.
/// * **Mudanças vindas do rádio** (botão de sintonia, tecla MODE, painel do IC-705, CI-V transceive)
///   são detectadas comparando o [RadioState] com o último valor visto; fora da janela de guarda
///   viram eventos entregues ao motor via [onRadioChange], que atualiza banda, indicadores, etc.
/// * O rádio é a **fonte da verdade** ao conectar ([SyncPolicy.radioFirst]): o app adota o que lê.
///   Em [SyncPolicy.appFirst] o app envia seus valores ao conectar.
///
/// A classe não possui timers nem I/O próprios; o relógio é injetável para testes
/// (`test/radio_sync_test.dart`).
library;

import '../radio/radio_link.dart';

/// Quem prevalece quando o app conecta ao rádio.
enum SyncPolicy {
  /// O app adota frequência/modo/potência lidos do rádio (padrão).
  radioFirst,

  /// O app envia ao rádio a banda/modo escolhidos nele.
  appFirst,
}

/// Parâmetros sincronizados.
enum SyncField { frequency, mode, dataMode, filter, rfPower, preamp, att }

/// Evento: o valor de [field] mudou **no rádio**.
class RadioChange {
  const RadioChange(this.field, this.value);
  final SyncField field;

  /// Novo valor (Hz para frequência; índice CI-V para modo; 0/1 para DATA; 0..255 potência; ...).
  final int value;

  @override
  String toString() => 'RadioChange($field, $value)';
}

class RadioSync {
  RadioSync({
    required this.link,
    required this.onRadioChange,
    DateTime Function()? clock,
    this.guard = const Duration(milliseconds: 2500),
  }) : _clock = clock ?? DateTime.now;

  /// Enlace com o rádio.
  final RadioLink link;

  /// Chamado quando o rádio altera um parâmetro por conta própria.
  final void Function(RadioChange change) onRadioChange;

  /// Duração da janela em que respostas divergentes são ignoradas após uma escrita do app.
  final Duration guard;

  final DateTime Function() _clock;

  // último valor visto no rádio e escritas pendentes do app, por parâmetro
  final Map<SyncField, int?> _seen = {};
  final Map<SyncField, int> _wanted = {};
  final Map<SyncField, DateTime> _wroteAt = {};

  bool _guarded(SyncField f) {
    final t = _wroteAt[f];
    return t != null && _clock().difference(t) < guard;
  }

  void _mark(SyncField f, int v) {
    _wanted[f] = v;
    _wroteAt[f] = _clock();
    _seen[f] = v;
  }

  // ------------------------------------------------------------------ app -> rádio

  /// Envia a frequência (Hz) ao rádio.
  void pushFrequency(int hz) {
    _mark(SyncField.frequency, hz);
    link.setFrequency(hz);
  }

  /// Envia modo (e filtro) ao rádio.
  void pushMode(int mode, {int filter = 1}) {
    _mark(SyncField.mode, mode);
    link.setMode(mode, filter: filter);
  }

  /// Liga/desliga DATA.
  void pushDataMode(bool on, {int filter = 1}) {
    _mark(SyncField.dataMode, on ? 1 : 0);
    link.setDataMode(on, filter: filter);
  }

  /// Seleciona USB + DATA (USB-D).
  void pushUsbData() {
    _mark(SyncField.mode, 1);
    _mark(SyncField.dataMode, 1);
    link.setUsbData();
  }

  /// Potência de RF (0..255).
  void pushRfPower(int raw) {
    _mark(SyncField.rfPower, raw);
    link.setRfPower(raw);
  }

  void pushPreamp(int v) {
    _mark(SyncField.preamp, v);
    link.setPreamp(v);
  }

  void pushAtt(int db) {
    _mark(SyncField.att, db);
    link.setAtt(db);
  }

  // ------------------------------------------------------------------ rádio -> app

  /// Adota imediatamente o estado atual do rádio como "visto" **sem** gerar eventos
  /// (usado logo após a primeira leitura completa) e depois notifica tudo de uma vez.
  void adoptAll() {
    final s = link.state;
    _emit(SyncField.frequency, s.freqHz, force: true);
    _emit(SyncField.mode, s.mode, force: true);
    _emit(SyncField.dataMode, s.dataMode == null ? null : (s.dataMode! ? 1 : 0), force: true);
    _emit(SyncField.filter, s.filter, force: true);
    _emit(SyncField.rfPower, s.rfPower, force: true);
    _emit(SyncField.preamp, s.preamp, force: true);
    _emit(SyncField.att, s.att, force: true);
  }

  /// Deve ser chamado a cada notificação do enlace (`link.changes`).
  void onLinkChanged() {
    final s = link.state;
    _emit(SyncField.frequency, s.freqHz);
    _emit(SyncField.mode, s.mode);
    _emit(SyncField.dataMode, s.dataMode == null ? null : (s.dataMode! ? 1 : 0));
    _emit(SyncField.filter, s.filter);
    _emit(SyncField.rfPower, s.rfPower);
    _emit(SyncField.preamp, s.preamp);
    _emit(SyncField.att, s.att);
  }

  void _emit(SyncField f, int? v, {bool force = false}) {
    if (v == null) return;
    if (!force) {
      if (_seen[f] == v) return;
      if (_guarded(f) && _wanted[f] != v) return; // resposta atrasada de polling anterior
    }
    _seen[f] = v;
    if (_guarded(f) && _wanted[f] == v) return; // eco da nossa própria escrita
    onRadioChange(RadioChange(f, v));
  }

  /// Último valor conhecido do rádio para [f] (ou `null`).
  int? lastSeen(SyncField f) => _seen[f];
}
