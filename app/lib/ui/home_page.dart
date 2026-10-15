/// Tela principal: cabeçalho, waterfall, abas (Atividade / Meu QSO) e barra de ações (TX, HALT,
/// TUNE, Log). Em paisagem organiza waterfall e listas lado a lado. Abre o diálogo de registro de
/// QSO quando o motor conclui um contato.
library;

import 'package:flutter/material.dart';

import '../core/settings.dart';
import '../engine/engine.dart';
import 'activity_list.dart';
import 'log_page.dart';
import 'qso_panel.dart';
import 'radio_sheet.dart';
import 'settings_page.dart';
import 'station_sheet.dart';
import 'guidance.dart';
import 'status_header.dart';
import 'theme.dart';
import 'waterfall_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.engine});
  final Engine engine;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  Engine get e => widget.engine;

  bool _logDialogOpen = false;

  @override
  void initState() {
    super.initState();
    e.pendingLog.addListener(_onPendingLog);
  }

  /// Abre o formulário de confirmação quando o motor conclui um QSO (ou o usuário pede para registrar).
  Future<void> _onPendingLog() async {
    final draft = e.pendingLog.value;
    if (draft == null || _logDialogOpen || !mounted) return;
    _logDialogOpen = true;
    final res = await showLogQsoDialog(context, draft);
    _logDialogOpen = false;
    if (res != null) {
      await e.commitLog(res);
    } else {
      e.discardPendingLog();
    }
  }

  @override
  void dispose() {
    e.pendingLog.removeListener(_onPendingLog);
    _tabs.dispose();
    super.dispose();
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SettingsPage(engine: e)));
  }

  void _openLog() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LogPage(log: e.qsoLog)));
  }

  @override
  Widget build(BuildContext context) {
    final header = StatusHeader(
      engine: e,
      onSettings: _openSettings,
      onRadio: () => showRadioSheet(context, e),
      onHelp: () => showTutorial(context, simulator: e.settings.radioKind == RadioKind.simulator),
    );
    final coach = CoachBanner(engine: e);
    final wf = WaterfallView(
      engine: e,
      onDecodeTap: (d) => showStationSheet(context, e, d),
    );
    final lists = Column(
      children: [
        Container(
          color: Pal.panel,
          child: TabBar(
            controller: _tabs,
            indicatorColor: Pal.accent,
            labelColor: Pal.text,
            unselectedLabelColor: Pal.dim,
            dividerColor: Pal.line,
            tabs: const [Tab(text: 'Atividade', height: 38), Tab(text: 'Meu QSO / TX', height: 38)],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              ActivityList(engine: e, onOpenStation: (d) => showStationSheet(context, e, d)),
              QsoPanel(engine: e),
            ],
          ),
        ),
      ],
    );
    final actions = _ActionBar(engine: e, onLog: _openLog);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            _layout(header, coach, wf, lists, actions),
            Positioned.fill(child: AlertFlash(alerts: e.alerts)),
            Positioned(top: 0, left: 0, right: 0, child: AlertBanner(alerts: e.alerts)),
          ],
        ),
      ),
    );
  }

  /// Organiza os blocos da tela em retrato (coluna) ou paisagem (duas colunas).
  Widget _layout(Widget header, Widget coach, Widget wf, Widget lists, Widget actions) {
    return OrientationBuilder(
          builder: (context, o) {
            if (o == Orientation.landscape) {
              return Row(
                children: [
                  Expanded(flex: 5, child: Column(children: [header, Expanded(child: wf)])),
                  const VerticalDivider(width: 1),
                  Expanded(flex: 4, child: Column(children: [coach, Expanded(child: lists), actions])),
                ],
              );
            }
            return Column(
              children: [
                header,
                coach,
                Expanded(flex: 5, child: wf),
                Expanded(flex: 6, child: lists),
                actions,
              ],
            );
          },
    );
  }
}

/// Barra inferior: opções rápidas (Auto TX, Auto-seq) e botões de ação (TX, CQ, HALT, TUNE, Log).
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.engine, required this.onLog});
  final Engine engine;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: engine,
      builder: (context, _) {
        final en = engine.txEnabled;
        final cqActive = en && engine.qso.dxCall.isEmpty;
        final s = engine.settings;
        Widget label(String t) => FittedBox(fit: BoxFit.scaleDown, child: Text(t, maxLines: 1, softWrap: false));
        const pad = EdgeInsets.symmetric(horizontal: 4);
        return Container(
          color: Pal.panel,
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ---- opções rápidas (também em Configurações)
              Row(
                children: [
                  _OptionCheck(
                    label: 'Auto TX',
                    tooltip: 'Ao tocar em responder (↩), o TX é armado automaticamente',
                    value: s.replyEnablesTx,
                    onChanged: engine.setAutoTx,
                  ),
                  const SizedBox(width: 10),
                  _OptionCheck(
                    label: 'Auto-seq',
                    tooltip: 'Avança sozinho Tx1 → Tx5 conforme as respostas',
                    value: s.autoSeq,
                    onChanged: engine.setAutoSeq,
                  ),
                  const SizedBox(width: 10),
                  _OptionCheck(
                    label: 'Travar etapa',
                    tooltip: 'Não avançar de etapa: repete a mensagem escolhida em Meu QSO / TX',
                    value: engine.qso.lockStep,
                    onChanged: engine.setLockStep,
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: pad,
                        backgroundColor: en ? Pal.tx : Pal.panel2,
                        foregroundColor: en ? Colors.white : Pal.text,
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: () => engine.setTxEnabled(!en),
                      icon: Icon(en ? Icons.cell_tower : Icons.power_settings_new, size: 18),
                      label: label(en ? 'TX ATIVO' : 'Ativar TX'),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: pad,
                        backgroundColor: cqActive ? Pal.tx : Pal.rx.withValues(alpha: 0.18),
                        foregroundColor: cqActive ? Colors.white : Pal.rx,
                        side: BorderSide(color: cqActive ? Pal.tx : Pal.rx),
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: engine.toggleCq,
                      icon: const Icon(Icons.campaign, size: 18),
                      label: label(cqActive ? 'CQ ■' : 'CQ'),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    flex: 3,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(padding: pad, minimumSize: const Size(0, 44), foregroundColor: Pal.warn),
                      onPressed: engine.haltTx,
                      child: label('HALT'),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    flex: 3,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: pad,
                        minimumSize: const Size(0, 44),
                        backgroundColor: engine.tuning ? Pal.tx.withValues(alpha: 0.25) : null,
                      ),
                      onPressed: () => engine.tune(!engine.tuning),
                      child: label('TUNE'),
                    ),
                  ),
                  const SizedBox(width: 5),
                  IconButton.outlined(
                    tooltip: 'Logbook',
                    visualDensity: VisualDensity.compact,
                    onPressed: onLog,
                    icon: const Icon(Icons.menu_book),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Caixa de seleção compacta com rótulo, para opções rápidas na tela principal.
class _OptionCheck extends StatelessWidget {
  const _OptionCheck({required this.label, required this.value, required this.onChanged, this.tooltip});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? label,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: value,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) => onChanged(v ?? false),
                ),
              ),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: value ? Pal.text : Pal.dim)),
            ],
          ),
        ),
      ),
    );
  }
}
