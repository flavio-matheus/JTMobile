/// Logbook local persistente (ADIF) do JTMobile.
///
/// * **Fonte da verdade**: um arquivo ADIF (`jtmobile_logbook.adi`) na pasta de documentos do app.
///   É lido ao iniciar ([load]) e mantido a cada alteração: inclusão = *append*; edição/exclusão =
///   reescrita atômica (arquivo temporário + renomear).
/// * **Consultas**: dupe-check ([isWorked]), países/bandas já trabalhados, busca textual.
/// * **Exportação**: ADIF completo ([exportAdif]) e CSV ([exportCsv]) para compartilhar (share sheet).
/// * **Importação**: [importAdif] funde registros de outro programa, descartando duplicados.
/// * **Integrações** (QRZ/LoTW/eQSL/Club Log): ver `log_services.dart` e `docs/LOGBOOK.md`.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/dxcc.dart';
import 'adif.dart';
import 'qso_record.dart';

/// Nome do arquivo ADIF do logbook.
const String kLogFileName = 'jtmobile_logbook.adi';

class QsoLog extends ChangeNotifier {
  /// [dirProvider] permite injetar outra pasta (testes). Por padrão usa a pasta de documentos do app.
  QsoLog({Future<Directory?> Function()? dirProvider}) : _dirProvider = dirProvider ?? _defaultDir;

  final Future<Directory?> Function() _dirProvider;

  static Future<Directory?> _defaultDir() async {
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      return null;
    }
  }

  final List<QsoRecord> _records = [];

  /// QSOs em ordem cronológica (mais antigo primeiro).
  List<QsoRecord> get records => List.unmodifiable(_records);

  /// Arquivo ADIF no disco (ou `null` se o armazenamento não estiver disponível).
  Future<File?> file() async {
    final d = await _dirProvider();
    return d == null ? null : File('${d.path}/$kLogFileName');
  }

  /// Carrega o logbook do disco (chamar uma vez ao iniciar o app).
  Future<void> load() async {
    final f = await file();
    if (f == null || !await f.exists()) return;
    final text = await f.readAsString();
    _records
      ..clear()
      ..addAll(Adif.parse(text).map(QsoRecord.fromAdif).whereType<QsoRecord>());
    _records.sort((a, b) => a.timeOn.compareTo(b.timeOn));
    notifyListeners();
  }

  // ------------------------------------------------------------------ escrita

  /// Inclui um QSO e o grava no arquivo.
  Future<void> add(QsoRecord r) async {
    _records.add(r);
    _records.sort((a, b) => a.timeOn.compareTo(b.timeOn));
    notifyListeners();
    final f = await file();
    if (f == null) return;
    if (!await f.exists()) await f.writeAsString(Adif.header());
    await f.writeAsString(Adif.serialize(r.toAdif()), mode: FileMode.append);
  }

  /// Substitui o QSO de mesmo `id` por [r] e reescreve o arquivo.
  Future<void> update(QsoRecord r) async {
    final i = _records.indexWhere((x) => x.id == r.id);
    if (i < 0) return;
    _records[i] = r;
    notifyListeners();
    await _rewrite();
  }

  /// Remove o QSO com o [id] dado.
  Future<void> remove(String id) async {
    _records.removeWhere((x) => x.id == id);
    notifyListeners();
    await _rewrite();
  }

  /// Marca os QSOs [ids] como enviados ao [service] (status "Y").
  Future<void> markUploaded(LogService service, Iterable<String> ids) async {
    final set = ids.toSet();
    for (var i = 0; i < _records.length; i++) {
      if (set.contains(_records[i].id)) {
        final extra = Map<String, String>.of(_records[i].extra)..[service.adifField] = 'Y';
        _records[i] = _records[i].copyWith(extra: extra);
      }
    }
    notifyListeners();
    await _rewrite();
  }

  /// Importa registros ADIF de [text]; ignora duplicados (mesmo indicativo, banda, modo e hora ±5 min).
  /// Retorna quantos QSOs novos foram incluídos.
  Future<int> importAdif(String text) async {
    var added = 0;
    for (final raw in Adif.parse(text)) {
      final r = QsoRecord.fromAdif(raw);
      if (r == null || _isDuplicate(r)) continue;
      _records.add(r);
      added++;
    }
    if (added > 0) {
      _records.sort((a, b) => a.timeOn.compareTo(b.timeOn));
      notifyListeners();
      await _rewrite();
    }
    return added;
  }

  bool _isDuplicate(QsoRecord r) => _records.any((x) =>
      x.call == r.call &&
      x.band == r.band &&
      x.mode == r.mode &&
      x.timeOn.difference(r.timeOn).abs() < const Duration(minutes: 5));

  Future<void> _rewrite() async {
    final f = await file();
    if (f == null) return;
    final tmp = File('${f.path}.tmp');
    final sb = StringBuffer(Adif.header());
    for (final r in _records) {
      sb.write(Adif.serialize(r.toAdif()));
    }
    await tmp.writeAsString(sb.toString(), flush: true);
    await tmp.rename(f.path); // atômico no mesmo volume
  }

  // ------------------------------------------------------------------ consulta

  /// `true` se já existe QSO com [call] (e, se informados, na mesma [band]/[mode]).
  bool isWorked(String call, {String? band, String? mode}) {
    final c = baseCall(call);
    return _records.any((r) =>
        baseCall(r.call) == c && (band == null || r.band == band) && (mode == null || r.mode == mode));
  }

  /// Países (DXCC aproximado por prefixo) já trabalhados.
  Set<String> workedCountries() => {
        for (final r in _records)
          if (lookupDxcc(r.call) != null) lookupDxcc(r.call)!.country,
      };

  /// Filtra por texto (indicativo, nome, grid, comentário, banda ou modo).
  List<QsoRecord> search(String q) {
    final s = q.trim().toUpperCase();
    if (s.isEmpty) return records;
    return _records
        .where((r) =>
            r.call.contains(s) ||
            r.name.toUpperCase().contains(s) ||
            r.grid.contains(s) ||
            r.comment.toUpperCase().contains(s) ||
            r.band.toUpperCase() == s ||
            r.mode == s)
        .toList();
  }

  // ------------------------------------------------------------------ exportação

  /// ADIF completo (cabeçalho + todos os QSOs, ou apenas [only]).
  String exportAdif({Iterable<QsoRecord>? only}) {
    final sb = StringBuffer(Adif.header());
    for (final r in (only ?? _records)) {
      sb.write(Adif.serialize(r.toAdif()));
    }
    return sb.toString();
  }

  /// CSV simples (UTF-8) para planilhas.
  String exportCsv() {
    String q(String v) => '"${v.replaceAll('"', '""')}"';
    final sb = StringBuffer('data_utc,hora_utc,indicativo,banda,freq_mhz,modo,rst_env,rst_rec,grid,nome,comentario\n');
    for (final r in _records) {
      final a = r.toAdif();
      sb.writeln([
        a['QSO_DATE'],
        a['TIME_ON'],
        r.call,
        r.band,
        (r.freqHz / 1e6).toStringAsFixed(6),
        r.mode,
        r.rstSent,
        r.rstRcvd,
        r.grid,
        r.name,
        r.comment,
      ].map((e) => q(e ?? '')).join(','));
    }
    return sb.toString();
  }

  /// Grava [content] em um arquivo temporário e devolve o caminho (para compartilhar).
  Future<File?> writeExport(String fileName, String content) async {
    final d = await _dirProvider();
    if (d == null) return null;
    final f = File('${d.path}/$fileName');
    await f.writeAsString(content, flush: true);
    return f;
  }
}
