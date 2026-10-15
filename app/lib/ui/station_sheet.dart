/// Ficha da estação (folha inferior) ao tocar numa decodificação: indicativo, país, locator,
/// distância/azimute, SNR, DT, frequência, histórico da sessão e ações (responder, Rx aqui).
library;

import 'package:flutter/material.dart';

import '../core/dxcc.dart';
import '../core/geo.dart';
import '../core/models.dart';
import '../engine/engine.dart';
import 'activity_list.dart';
import 'theme.dart';

/// Ficha da estação ao tocar numa decodificação: todas as informações do sinal e do operador.
Future<void> showStationSheet(BuildContext context, Engine e, Decode d) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Pal.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => _StationSheet(engine: e, d: d),
  );
}

class _StationSheet extends StatelessWidget {
  const _StationSheet({required this.engine, required this.d});
  final Engine engine;
  final Decode d;

  @override
  Widget build(BuildContext context) {
    final call = d.senderCall ?? '—';
    final info = d.senderCall == null ? null : lookupDxcc(d.senderCall!);
    final heard = engine.decodes.where((x) => x.senderCall == d.senderCall).toList();
    final first = heard.isEmpty ? d : heard.first;
    final best = heard.isEmpty ? d : heard.reduce((a, b) => a.snr >= b.snr ? a : b);
    final my = gridToLatLon(engine.settings.grid);
    final other = d.parsed.grid != null ? gridToLatLon(d.parsed.grid!) : null;
    String dist = '—';
    if (my != null && other != null) {
      final r = distanceBearing(my.lat, my.lon, other.lat, other.lon);
      dist = '${r.km.round()} km  ·  ${r.bearing.round()}° ${bearingCompass(r.bearing)}';
    }
    final worked = engine.qsoLog.records.any((r) => baseCall(r.call) == baseCall(call));
    final snr = d.snr.round();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Pal.line, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(call, style: kMono.copyWith(fontSize: 32, fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
                if (d.isCq) _chip('CQ${d.parsed.cqModifier != null ? ' ${d.parsed.cqModifier}' : ''}', Pal.cq),
                if (d.toMe) _chip('CHAMANDO VOCÊ', Pal.tx),
                if (worked) _chip('JÁ TRABALHADO', Pal.dim),
              ],
            ),
            const SizedBox(height: 2),
            Text(info == null ? 'País desconhecido' : '${info.country}  ·  ${info.continent}',
                style: const TextStyle(fontSize: 16, color: Pal.accent)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Pal.bg, borderRadius: BorderRadius.circular(10)),
              child: Text(d.message, style: kMono.copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 22,
              runSpacing: 10,
              children: [
                _kv('Locator', d.parsed.grid ?? '—'),
                _kv('Distância / Azimute', dist),
                _kv('SNR', '${snr >= 0 ? '+' : ''}$snr dB'),
                _kv('DT', '${d.dt >= 0 ? '+' : ''}${d.dt.toStringAsFixed(2)} s'),
                _kv('Frequência', '${d.freq.round()} Hz'),
                _kv('Slot', '${hhmmss(d.slotStart)} UTC · ${engine.slotIndexAt(d.slotStart) % 2 == 0 ? '1º (par)' : '2º (ímpar)'}'),
                _kv('Ouvida', '${heard.length}× nesta sessão'),
                _kv('Melhor SNR', '${best.snr.round()} dB'),
                _kv('Primeira vez', hhmmss(first.slotStart)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: d.parsed.from == null || d.fromMe
                        ? null
                        : () {
                            engine.selectDecode(d, startQso: true);
                            Navigator.pop(context);
                          },
                    icon: const Icon(Icons.reply),
                    label: const Text('Responder / iniciar QSO'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    engine.setRxFreq(d.freq.round());
                    Navigator.pop(context);
                  },
                  child: const Text('Rx aqui'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
        margin: const EdgeInsets.only(right: 6, bottom: 5),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.2), border: Border.all(color: c), borderRadius: BorderRadius.circular(5)),
        child: Text(t, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800)),
      );

  Widget _kv(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(k, style: const TextStyle(color: Pal.dim, fontSize: 11)),
          Text(v, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      );
}
