/// Painel do rádio: mostra o estado real do rádio e permite ajustá-lo a partir do app.
///
/// Tudo aqui é **bidirecional** (veja `engine/radio_sync.dart`): os valores exibidos vêm do rádio
/// (lidos por CI-V) e qualquer alteração feita aqui é enviada ao rádio; alterações feitas no
/// painel do rádio aparecem aqui em até ~1–4 s (ou na hora, com o CI-V Transceive ligado).
library;

import 'package:flutter/material.dart';

import '../engine/engine.dart';
import '../radio/civ.dart';
import '../radio/radio_link.dart';
import 'theme.dart';

Future<void> showRadioSheet(BuildContext context, Engine e) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Pal.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => _RadioSheet(engine: e),
  );
}

class _RadioSheet extends StatefulWidget {
  const _RadioSheet({required this.engine});
  final Engine engine;

  @override
  State<_RadioSheet> createState() => _RadioSheetState();
}

class _RadioSheetState extends State<_RadioSheet> {
  double? _dragPower; // valor local enquanto o usuário arrasta o controle de potência

  Engine get e => widget.engine;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedBuilder(
        animation: e,
        builder: (context, _) {
          final r = e.radio;
          final connected = r?.status == LinkStatus.connected;
          final st = r?.state;
          final freq = st?.freqHz;
          final std = e.dialFrequency;
          final power = _dragPower ?? (e.rfPowerPercent?.toDouble() ?? 0);
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Pal.line, borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.sync_alt, color: Pal.accent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Rádio ⇄ App', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      ),
                      _badge(connected ? 'Sincronizado' : 'Sem conexão', connected ? Pal.rx : Pal.dim),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Os ajustes são espelhados nos dois sentidos: o que você muda aqui vai ao rádio, e o que muda no rádio aparece aqui.',
                    style: TextStyle(color: Pal.dim, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  _section('Frequência'),
                  Row(
                    children: [
                      Expanded(
                        child: Text(freq == null ? '—' : _fmt(freq),
                            style: kMono.copyWith(fontSize: 24, fontWeight: FontWeight.w600)),
                      ),
                      OutlinedButton.icon(
                        onPressed: connected ? () => _askFrequency(context) : null,
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Digitar'),
                      ),
                    ],
                  ),
                  if (std != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Padrão ${e.mode.label} nesta banda: ${_fmt(std)}',
                                style: TextStyle(color: e.radioOffStandardFrequency ? Pal.warn : Pal.dim, fontSize: 12)),
                          ),
                          if (e.radioOffStandardFrequency)
                            TextButton(onPressed: connected ? e.goToStandardSetup : null, child: const Text('Ir para o padrão')),
                        ],
                      ),
                    ),
                  _section('Modo'),
                  Row(
                    children: [
                      Expanded(
                        child: Text(civModeName(st?.mode, st?.dataMode) + (st?.filter != null ? '   FIL${st!.filter}' : ''),
                            style: kMono.copyWith(fontSize: 18)),
                      ),
                      if (connected)
                        e.radioModeOk
                            ? _badge('USB-D ✓', Pal.rx)
                            : FilledButton.tonal(onPressed: e.fixRadioMode, child: const Text('Ajustar para USB-D')),
                    ],
                  ),
                  _section('Potência de RF'),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: power.clamp(0, 100),
                          min: 0,
                          max: 100,
                          divisions: 100,
                          label: '${power.round()}%',
                          onChanged: connected ? (v) => setState(() => _dragPower = v) : null,
                          onChangeEnd: (v) {
                            e.setRfPowerPercent(v.round());
                            setState(() => _dragPower = null);
                          },
                        ),
                      ),
                      SizedBox(width: 48, child: Text('${power.round()}%', style: kMono, textAlign: TextAlign.right)),
                    ],
                  ),
                  const Text(
                    'Dica: em FT8/FT4 use potência moderada (≤ 50 %). O ciclo de trabalho é 100 % durante a TX.',
                    style: TextStyle(color: Pal.dim, fontSize: 11),
                  ),
                  _section('Recepção'),
                  Row(
                    children: [
                      const SizedBox(width: 72, child: Text('Pré-amp')),
                      Expanded(
                        child: SegmentedButton<int>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          segments: const [
                            ButtonSegment(value: 0, label: Text('Off')),
                            ButtonSegment(value: 1, label: Text('P1')),
                            ButtonSegment(value: 2, label: Text('P2')),
                          ],
                          selected: {st?.preamp ?? 0},
                          onSelectionChanged: connected ? (s) => e.setPreamp(s.first) : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SizedBox(width: 72, child: Text('ATT')),
                      Expanded(
                        child: SegmentedButton<int>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          segments: const [
                            ButtonSegment(value: 0, label: Text('Off')),
                            ButtonSegment(value: 20, label: Text('20 dB')),
                          ],
                          selected: {st?.att ?? 0},
                          onSelectionChanged: connected ? (s) => e.setAtt(s.first) : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: connected ? e.syncNow : null,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Sincronizar agora'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: connected ? e.goToStandardSetup : null,
                          icon: const Icon(Icons.tune),
                          label: Text('Padrão ${e.mode.label}'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(t.toUpperCase(), style: const TextStyle(color: Pal.accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
      );

  Widget _badge(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.18), border: Border.all(color: c), borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800)),
      );

  static String _fmt(int hz) {
    final s = hz.toString().padLeft(7, '0');
    return '${s.substring(0, s.length - 6)}.${s.substring(s.length - 6, s.length - 3)}.${s.substring(s.length - 3)}';
  }

  Future<void> _askFrequency(BuildContext context) async {
    final ctl = TextEditingController(text: ((e.radio?.state.freqHz ?? 0) / 1000).toStringAsFixed(3));
    final res = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Frequência de dial (kHz)'),
        content: TextField(
          controller: ctl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(hintText: 'ex.: 14074.000', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctl.text.replaceAll(',', '.'))),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (res != null && res > 100) e.setDialFrequency((res * 1000).round());
  }
}
