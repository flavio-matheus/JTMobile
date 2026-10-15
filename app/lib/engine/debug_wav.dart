import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/ftx_native.dart';

/// Ferramenta de depuração (somente em builds debug): decodifica arquivos WAV (PCM16 mono 12 kHz)
/// colocados em `<pasta externa do app>/wav/` e grava o resultado em `<arquivo>.out`.
Future<void> debugDecodeWavFiles(FtxCodec codec) async {
  try {
    final dir = await getExternalStorageDirectory();
    debugPrint('debugWav dir=${dir?.path}');
    if (dir == null) return;
    final d = Directory('${dir.path}/wavtest');
    await d.create(recursive: true);
    for (final f in d.listSync().whereType<File>().where((f) => f.path.endsWith('.wav'))) {
      final bytes = await f.readAsBytes();
      final bd = ByteData.sublistView(bytes);
      final n = (bytes.length - 44) ~/ 2;
      final s = Float32List(n);
      for (var i = 0; i < n; i++) {
        s[i] = bd.getInt16(44 + i * 2, Endian.little) / 32768.0;
      }
      final sw = Stopwatch()..start();
      final res = codec.decode(s, FtxProtocol.ft8);
      final sb = StringBuffer();
      for (final r in res) {
        sb.writeln('${r.snrDb.round().toString().padLeft(3)} ${r.dtSec.toStringAsFixed(1).padLeft(4)} ${r.freqHz.round().toString().padLeft(4)} ~  ${r.text}');
      }
      sb.writeln('# ${res.length} decodes em ${sw.elapsedMilliseconds} ms');
      await File('${f.path}.out').writeAsString(sb.toString());
    }
  } catch (e, st) {
    debugPrint('debugDecodeWavFiles: $e\n$st');
  }
}
