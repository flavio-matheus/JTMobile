/// Lista de atividade da banda (equivalente à janela "Band Activity" do JTDX), pensada para celular:
/// agrupada por slot, com filtros, destaques (CQ, para mim, já trabalhado, novo país) e informações
/// do operador (país, distância, azimute).
library;

import 'package:flutter/material.dart';

import '../core/dxcc.dart';
import '../core/geo.dart';
import '../core/models.dart';
import '../engine/engine.dart';
import 'theme.dart';

enum ActivityFilter { all, cq, mine, nearRx }

String two(int n) => n.toString().padLeft(2, '0');
String hhmmss(DateTime t) => '${two(t.hour)}${two(t.minute)}${two(t.second)}';

/// Lista de atividade da banda (equivalente à janela "Band Activity" do JTDX), pensada para o celular.
class ActivityList extends StatefulWidget {
  const ActivityList({super.key, required this.engine, required this.onOpenStation});
  final Engine engine;
  final void Function(Decode d) onOpenStation;

  @override
  State<ActivityList> createState() => _ActivityListState();
}

class _ActivityListState extends State<ActivityList> {
  ActivityFilter _filter = ActivityFilter.all;

  Engine get e => widget.engine;

  bool _pass(Decode d) {
    switch (_filter) {
      case ActivityFilter.all:
        return true;
      case ActivityFilter.cq:
        return d.isCq;
      case ActivityFilter.mine:
        return d.toMe || d.fromMe;
      case ActivityFilter.nearRx:
        return (d.freq - e.settings.rxFreq).abs() <= 120 || d.toMe;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([e, e.qsoLog]),
      builder: (context, _) {
        final worked = <String>{};
        final workedCountries = <String>{};
        for (final r in e.qsoLog.records) {
          worked.add(baseCall(r.call));
          final c = lookupDxcc(r.call);
          if (c != null) workedCountries.add(c.country);
        }
        // agrupa por slot (mais novo primeiro)
        final groups = <DateTime, List<Decode>>{};
        for (final d in e.decodes.reversed) {
          if (!_pass(d)) continue;
          groups.putIfAbsent(d.slotStart, () => []).add(d);
        }
        final slots = groups.keys.toList()..sort((a, b) => b.compareTo(a));
        final items = <Object>[];
        for (final s in slots) {
          items.add(s);
          items.addAll(groups[s]!);
        }
        return Column(
          children: [
            _filters(),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        e.monitoring ? 'Aguardando decodificações…\n(o primeiro ciclo completo leva até ${e.mode.slotSeconds.toStringAsFixed(0)} s)' : 'Conecte o rádio para começar.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Pal.dim),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final it = items[i];
                        if (it is DateTime) {
                          final n = groups[it]!.length;
                          return Container(
                            color: Pal.panel2,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            child: Row(
                              children: [
                                Text(hhmmss(it), style: kMono.copyWith(fontSize: 11, color: Pal.dim)),
                                const SizedBox(width: 8),
                                Text('$n mensage${n == 1 ? 'm' : 'ns'}', style: const TextStyle(fontSize: 11, color: Pal.dim)),
                                const Spacer(),
                                Text('slot ${e.slotIndexAt(it) % 2 == 0 ? '1º' : '2º'}', style: const TextStyle(fontSize: 11, color: Pal.dim)),
                              ],
                            ),
                          );
                        }
                        final d = it as Decode;
                        return _Row(
                          d: d,
                          engine: e,
                          workedCall: d.senderCall != null && worked.contains(baseCall(d.senderCall!)),
                          newCountry: d.dxcc != null && !workedCountries.contains(d.dxcc!.country) && workedCountries.isNotEmpty,
                          onTap: () => widget.onOpenStation(d),
                          onReply: () => e.selectDecode(d, startQso: true),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _filters() {
    Widget chip(String label, ActivityFilter f, {int? count}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(count == null ? label : '$label ($count)'),
            selected: _filter == f,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => setState(() => _filter = f),
          ),
        );
    final mine = e.decodes.where((d) => d.toMe).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  chip('Todas', ActivityFilter.all),
                  chip('CQ', ActivityFilter.cq),
                  chip('Para mim', ActivityFilter.mine, count: mine),
                  chip('Perto do Rx', ActivityFilter.nearRx),
                ],
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Limpar',
            onPressed: e.clearDecodes,
            icon: const Icon(Icons.delete_sweep, size: 20, color: Pal.dim),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.d,
    required this.engine,
    required this.workedCall,
    required this.newCountry,
    required this.onTap,
    required this.onReply,
  });
  final Decode d;
  final Engine engine;
  final bool workedCall;
  final bool newCountry;
  final VoidCallback onTap;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final toMe = d.toMe;
    final cq = d.isCq;
    final Color accent = toMe ? Pal.tx : (cq ? Pal.cq : Pal.line);
    final bg = toMe ? Pal.tx.withValues(alpha: 0.13) : (cq ? Pal.rx.withValues(alpha: 0.06) : Colors.transparent);
    final nearRx = (d.freq - engine.settings.rxFreq).abs() <= 60;
    final info = <String>[];
    if (d.dxcc != null) info.add('${d.dxcc!.country} (${d.dxcc!.continent})');
    if (d.km != null) {
      info.add('${d.km!.round()} km · ${d.bearing!.round()}° ${bearingCompass(d.bearing!)}');
    }
    final snr = d.snr.round();
    final snrColor = snr >= -5 ? Pal.rx : (snr >= -15 ? Pal.text : Pal.warn);
    return InkWell(
      onTap: onTap,
      onLongPress: onReply,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border(left: BorderSide(color: accent, width: 4), bottom: const BorderSide(color: Pal.line, width: 0.5)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(hhmmss(d.slotStart), style: kMono.copyWith(fontSize: 11, color: Pal.dim)),
                      const SizedBox(width: 8),
                      Text('${snr >= 0 ? '+' : ''}$snr dB', style: kMono.copyWith(fontSize: 12, color: snrColor, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Text('DT ${d.dt >= 0 ? '+' : ''}${d.dt.toStringAsFixed(1)}',
                          style: kMono.copyWith(fontSize: 11, color: d.dt.abs() > 1.0 ? Pal.warn : Pal.dim)),
                      const SizedBox(width: 8),
                      Text('${d.freq.round()} Hz', style: kMono.copyWith(fontSize: 11, color: nearRx ? Pal.rx : Pal.dim)),
                      const Spacer(),
                      if (workedCall) const _Tag('JÁ TRAB.', Pal.dim),
                      if (newCountry) const _Tag('NOVO PAÍS', Pal.warn),
                      if (cq) const _Tag('CQ', Pal.cq),
                      if (toMe) const _Tag('PARA MIM', Pal.tx),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    d.message,
                    style: kMono.copyWith(fontSize: 16, fontWeight: toMe || cq ? FontWeight.w700 : FontWeight.w500, color: toMe ? Pal.tx : (cq ? Pal.cq : Pal.text)),
                  ),
                  if (info.isNotEmpty)
                    Text(info.join('  ·  '), style: const TextStyle(fontSize: 11, color: Pal.dim)),
                ],
              ),
            ),
            if (d.parsed.from != null && !d.fromMe)
              IconButton(
                tooltip: 'Responder',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.reply, color: cq || toMe ? Pal.accent : Pal.dim),
                onPressed: onReply,
              ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          border: Border.all(color: color.withValues(alpha: 0.7), width: 0.8),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800)),
      );
}
