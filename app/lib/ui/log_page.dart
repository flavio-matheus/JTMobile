import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../engine/qso_log.dart';
import 'activity_list.dart';
import 'theme.dart';

class LogPage extends StatelessWidget {
  const LogPage({super.key, required this.log});
  final QsoLog log;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: log,
      builder: (context, _) {
        final recs = log.records.reversed.toList();
        return Scaffold(
          appBar: AppBar(
            title: Text('Log (${recs.length})'),
            actions: [
              IconButton(
                tooltip: 'Compartilhar ADIF',
                icon: const Icon(Icons.ios_share),
                onPressed: recs.isEmpty
                    ? null
                    : () async {
                        final f = await log.file();
                        if (f != null && await f.exists()) {
                          await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'Log FT Mobile (ADIF)'));
                        }
                      },
              ),
            ],
          ),
          body: recs.isEmpty
              ? const Center(child: Text('Nenhum QSO registrado ainda.', style: TextStyle(color: Pal.dim)))
              : ListView.separated(
                  itemCount: recs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = recs[i];
                    return ListTile(
                      title: Text(r.call, style: kMono.copyWith(fontWeight: FontWeight.w700, fontSize: 18)),
                      subtitle: Text(
                          '${r.time.year}-${two(r.time.month)}-${two(r.time.day)} ${hhmmss(r.time)} UTC · ${(r.freqHz / 1e6).toStringAsFixed(3)} MHz · ${r.mode}\n'
                          'Enviado ${r.rstSent}  Recebido ${r.rstRcvd}  ${r.grid}'),
                      isThreeLine: true,
                    );
                  },
                ),
        );
      },
    );
  }
}
