/// Tela do logbook: lista, busca, edição, exclusão e exportação (ADIF/CSV).
///
/// Também contém o diálogo "Registrar QSO" ([showLogQsoDialog]) mostrado ao concluir um contato.
library;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/dxcc.dart';
import '../core/modes.dart';
import '../logbook/log_services.dart';
import '../logbook/qso_log.dart';
import '../logbook/qso_record.dart';
import 'activity_list.dart';
import 'theme.dart';

class LogPage extends StatefulWidget {
  const LogPage({super.key, required this.log});
  final QsoLog log;

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  String _query = '';

  QsoLog get log => widget.log;

  Future<void> _export(String kind) async {
    final stamp = DateTime.now().toUtc();
    final base = 'jtmobile_${stamp.year}${two(stamp.month)}${two(stamp.day)}';
    final f = kind == 'adif'
        ? await log.writeExport('$base.adi', log.exportAdif())
        : await log.writeExport('$base.csv', log.exportCsv());
    if (f != null) {
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'Logbook JTMobile (${kind.toUpperCase()})'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: log,
      builder: (context, _) {
        final recs = log.search(_query).reversed.toList();
        return Scaffold(
          appBar: AppBar(
            title: Text('Logbook (${log.records.length})'),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Exportar',
                icon: const Icon(Icons.ios_share),
                onSelected: _export,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'adif', child: Text('Exportar ADIF (.adi)')),
                  PopupMenuItem(value: 'csv', child: Text('Exportar CSV')),
                ],
              ),
              IconButton(
                tooltip: 'Integrações de logbook',
                icon: const Icon(Icons.cloud_upload_outlined),
                onPressed: () => showDialog<void>(context: context, builder: (_) => const _ServicesDialog()),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar indicativo, nome, grid, banda, modo…',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: recs.isEmpty
                    ? const Center(child: Text('Nenhum QSO.', style: TextStyle(color: Pal.dim)))
                    : ListView.separated(
                        itemCount: recs.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) => _tile(context, recs[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(BuildContext context, QsoRecord r) {
    final country = lookupDxcc(r.call);
    return Dismissible(
      key: ValueKey(r.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Pal.tx,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async =>
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Excluir QSO com ${r.call}?'),
              content: const Text('Esta ação remove o registro do logbook do app.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
              ],
            ),
          ) ??
          false,
      onDismissed: (_) => log.remove(r.id),
      child: ListTile(
        onTap: () async {
          final edited = await showLogQsoDialog(context, r, title: 'Editar QSO');
          if (edited != null) await log.update(edited);
        },
        title: Row(
          children: [
            Text(r.call, style: kMono.copyWith(fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(width: 8),
            Text('${r.band} ${r.mode}', style: const TextStyle(color: Pal.accent, fontSize: 12)),
            const Spacer(),
            for (final s in LogService.values)
              if (r.uploadStatus(s) == 'Y')
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Tooltip(message: 'Enviado a ${s.label}', child: const Icon(Icons.cloud_done, size: 15, color: Pal.rx)),
                ),
          ],
        ),
        subtitle: Text(
          '${r.timeOn.year}-${two(r.timeOn.month)}-${two(r.timeOn.day)} ${hhmmss(r.timeOn)} UTC · ${(r.freqHz / 1e6).toStringAsFixed(3)} MHz'
          '${country != null ? ' · ${country.country}' : ''}\n'
          'Env ${r.rstSent.isEmpty ? '—' : r.rstSent}  Rec ${r.rstRcvd.isEmpty ? '—' : r.rstRcvd}'
          '${r.grid.isNotEmpty ? '  ${r.grid}' : ''}${r.name.isNotEmpty ? '  ${r.name}' : ''}',
        ),
        isThreeLine: true,
      ),
    );
  }
}

/// Mostra o formulário de QSO (confirmação ao concluir um contato, ou edição). Retorna o registro
/// confirmado ou `null` se cancelado.
Future<QsoRecord?> showLogQsoDialog(BuildContext context, QsoRecord draft, {String title = 'Registrar QSO'}) {
  final call = TextEditingController(text: draft.call);
  final grid = TextEditingController(text: draft.grid);
  final name = TextEditingController(text: draft.name);
  final comment = TextEditingController(text: draft.comment);
  final rsts = TextEditingController(text: draft.rstSent);
  final rstr = TextEditingController(text: draft.rstRcvd);
  final mhz = TextEditingController(text: (draft.freqHz / 1e6).toStringAsFixed(6));
  var mode = draft.mode;
  return showDialog<QsoRecord>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: call,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Indicativo', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: grid,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Grid', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: kModes.any((m) => m.id == mode) ? mode : null,
                      decoration: const InputDecoration(labelText: 'Modo', border: OutlineInputBorder()),
                      items: [for (final m in kModes) DropdownMenuItem(value: m.id, child: Text(m.label))],
                      onChanged: (v) => setS(() => mode = v ?? mode),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextField(controller: rsts, decoration: const InputDecoration(labelText: 'RST enviado', border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: rstr, decoration: const InputDecoration(labelText: 'RST recebido', border: OutlineInputBorder()))),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: mhz,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Frequência (MHz)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: comment, decoration: const InputDecoration(labelText: 'Comentário', border: OutlineInputBorder())),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final f = double.tryParse(mhz.text.replaceAll(',', '.'));
              Navigator.pop(
                ctx,
                draft.copyWith(
                  call: call.text.trim().toUpperCase(),
                  grid: grid.text.trim().toUpperCase(),
                  name: name.text.trim(),
                  comment: comment.text.trim(),
                  rstSent: rsts.text.trim(),
                  rstRcvd: rstr.text.trim(),
                  mode: mode,
                  freqHz: f == null ? draft.freqHz : (f * 1e6).round(),
                ),
              );
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
}

/// Lista as integrações de logbook previstas (fase 2) e o estado de cada uma.
class _ServicesDialog extends StatelessWidget {
  const _ServicesDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Integrações de logbook'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Em desenvolvimento (fase 2). Por enquanto exporte o ADIF e importe no serviço desejado. '
              'O app já guarda, em cada QSO, o status de envio por serviço.',
              style: TextStyle(color: Pal.dim, fontSize: 12),
            ),
            const SizedBox(height: 12),
            for (final s in kPlannedLogServices)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(s.implemented ? Icons.check_circle : Icons.schedule, color: s.implemented ? Pal.rx : Pal.dim),
                title: Text(s.service.label),
                subtitle: Text(s.note, style: const TextStyle(fontSize: 11)),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}
