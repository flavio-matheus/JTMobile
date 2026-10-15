import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'activity_list.dart';
import 'log_page.dart';
import 'qso_panel.dart';
import 'settings_page.dart';
import 'station_sheet.dart';
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

  @override
  void dispose() {
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
    final header = StatusHeader(engine: e, onSettings: _openSettings);
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
        child: OrientationBuilder(
          builder: (context, o) {
            if (o == Orientation.landscape) {
              return Row(
                children: [
                  Expanded(flex: 5, child: Column(children: [header, Expanded(child: wf)])),
                  const VerticalDivider(width: 1),
                  Expanded(flex: 4, child: Column(children: [Expanded(child: lists), actions])),
                ],
              );
            }
            return Column(
              children: [
                header,
                Expanded(flex: 5, child: wf),
                Expanded(flex: 6, child: lists),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}

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
        final keyed = engine.transmitting || engine.tuning;
        return Container(
          color: Pal.panel,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: en ? Pal.tx : Pal.panel2,
                    foregroundColor: en ? Colors.white : Pal.text,
                    minimumSize: const Size(0, 46),
                  ),
                  onPressed: () => engine.setTxEnabled(!en),
                  icon: Icon(en ? Icons.cell_tower : Icons.power_settings_new),
                  label: Text(en ? 'TX ATIVO' : 'Ativar TX', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 46), foregroundColor: Pal.warn),
                  onPressed: engine.haltTx,
                  child: const Text('HALT', softWrap: false),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 46),
                    backgroundColor: engine.tuning ? Pal.tx.withValues(alpha: 0.25) : null,
                  ),
                  onPressed: () => engine.tune(!engine.tuning),
                  child: const Text('TUNE', softWrap: false),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.outlined(
                tooltip: 'Log de QSOs',
                onPressed: onLog,
                icon: const Icon(Icons.menu_book),
              ),
              if (keyed) const SizedBox(width: 2),
            ],
          ),
        );
      },
    );
  }
}
