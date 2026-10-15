import 'package:flutter/material.dart';

import '../core/dxcc.dart';
import '../core/geo.dart';
import '../engine/engine.dart';
import '../engine/qso.dart';
import 'theme.dart';

/// Painel do QSO: estação em contato, mensagens Tx1..Tx6 e opções de sequência.
class QsoPanel extends StatefulWidget {
  const QsoPanel({super.key, required this.engine});
  final Engine engine;

  @override
  State<QsoPanel> createState() => _QsoPanelState();
}

class _QsoPanelState extends State<QsoPanel> {
  late final TextEditingController _dx;
  String _lastDx = '';

  Engine get e => widget.engine;

  @override
  void initState() {
    super.initState();
    _dx = TextEditingController(text: e.qso.dxCall);
  }

  @override
  void dispose() {
    _dx.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: e,
      builder: (context, _) {
        final q = e.qso;
        if (q.dxCall != _lastDx && !FocusScope.of(context).hasFocus) {
          _dx.text = q.dxCall;
        }
        _lastDx = q.dxCall;
        final dxInfo = q.dxCall.isEmpty ? null : lookupDxcc(q.dxCall);
        String? dist;
        final my = gridToLatLon(q.myGrid);
        final other = gridToLatLon(q.dxGrid);
        if (my != null && other != null) {
          final r = distanceBearing(my.lat, my.lon, other.lat, other.lon);
          dist = '${r.km.round()} km · ${r.bearing.round()}° ${bearingCompass(r.bearing)}';
        }
        return ListView(
          padding: const EdgeInsets.all(10),
          children: [
            _stationCard(q, dxInfo, dist),
            const SizedBox(height: 8),
            _txMessages(q),
            const SizedBox(height: 8),
            _options(),
            if (e.lastError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(e.lastError!, style: const TextStyle(color: Pal.warn)),
              ),
            if (e.txLog.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Últimas transmissões', style: TextStyle(color: Pal.dim, fontSize: 12)),
              const SizedBox(height: 4),
              for (final l in e.txLog.reversed.take(6)) Text(l, style: kMono.copyWith(fontSize: 12, color: Pal.tx)),
            ],
          ],
        );
      },
    );
  }

  Widget _stationCard(QsoManager q, DxccInfo? dxInfo, String? dist) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Pal.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dx,
                  textCapitalization: TextCapitalization.characters,
                  style: kMono.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(labelText: 'Estação (DX)', isDense: true, border: OutlineInputBorder()),
                  onChanged: (v) {
                    q.dxCall = v.trim().toUpperCase();
                    if (q.dxCall.isNotEmpty && q.txIndex == 6) q.txIndex = 1;
                    if (q.dxCall.isEmpty) q.txIndex = 6;
                    e.refresh();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: TextEditingController(text: q.dxGrid),
                  textCapitalization: TextCapitalization.characters,
                  style: kMono.copyWith(fontSize: 18),
                  decoration: const InputDecoration(labelText: 'Grid', isDense: true, border: OutlineInputBorder()),
                  onChanged: (v) => q.dxGrid = v.trim().toUpperCase(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (q.dxCall.isEmpty)
            const Text('Nenhuma estação selecionada. Toque em “Responder” numa chamada, ou use CQ.',
                style: TextStyle(color: Pal.dim, fontSize: 12))
          else
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _kv('País', dxInfo == null ? '—' : '${dxInfo.country} (${dxInfo.continent})'),
                _kv('Distância', dist ?? '—'),
                _kv('Enviado', q.rptSent),
                _kv('Recebido', q.rptRcvd.isEmpty ? '—' : q.rptRcvd),
              ],
            ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(k, style: const TextStyle(color: Pal.dim, fontSize: 10)),
          Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      );

  Widget _txMessages(QsoManager q) {
    final labels = ['Tx1  grid', 'Tx2  relatório', 'Tx3  R relatório', 'Tx4  RR73', 'Tx5  73', 'Tx6  CQ'];
    return Container(
      decoration: BoxDecoration(color: Pal.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.line)),
      child: Column(
        children: [
          for (var i = 1; i <= 6; i++)
            InkWell(
              onTap: () => e.selectTxMessage(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: q.txIndex == i ? Pal.tx.withValues(alpha: 0.15) : null,
                  border: i < 6 ? const Border(bottom: BorderSide(color: Pal.line, width: 0.5)) : null,
                ),
                child: Row(
                  children: [
                    Icon(q.txIndex == i ? Icons.radio_button_checked : Icons.radio_button_off,
                        size: 18, color: q.txIndex == i ? Pal.tx : Pal.dim),
                    const SizedBox(width: 8),
                    SizedBox(width: 92, child: Text(labels[i - 1], style: const TextStyle(fontSize: 11, color: Pal.dim))),
                    Expanded(
                      child: Text(q.message(i), style: kMono.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _options() {
    final s = e.settings;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Pal.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.line)),
      child: Column(
        children: [
          Row(
            children: [
              const Text('Transmitir no', style: TextStyle(color: Pal.dim, fontSize: 12)),
              const SizedBox(width: 8),
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: 0, label: Text('1º slot (par)')),
                  ButtonSegment(value: 1, label: Text('2º slot (ímpar)')),
                ],
                selected: {e.txParity},
                onSelectionChanged: (v) => e.setTxParity(v.first),
              ),
            ],
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-sequência'),
            subtitle: const Text('Avança Tx1→Tx5 conforme as respostas', style: TextStyle(fontSize: 11)),
            value: s.autoSeq,
            onChanged: (v) {
              s.autoSeq = v;
              s.save();
            },
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Manter frequência de TX'),
            subtitle: const Text('Não segue a frequência da estação chamada', style: TextStyle(fontSize: 11)),
            value: s.holdTxFreq,
            onChanged: (v) {
              s.holdTxFreq = v;
              s.save();
            },
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: e.callCq,
                icon: const Icon(Icons.campaign, size: 18),
                label: const Text('CQ'),
              ),
              OutlinedButton.icon(
                onPressed: e.qso.dxCall.isEmpty ? null : e.logQsoNow,
                icon: const Icon(Icons.menu_book, size: 18),
                label: const Text('Registrar QSO'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  e.qso.clear();
                  e.refresh();
                },
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Limpar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
