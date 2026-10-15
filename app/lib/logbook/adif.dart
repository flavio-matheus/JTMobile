/// Leitura e escrita do formato ADIF (Amateur Data Interchange Format, v3.1.x).
///
/// ADIF é o formato universal de logbooks de radioamador: LoTW, QRZ.com, eQSL, Club Log, HRDLog,
/// WSJT-X, JTDX etc. importam/exportam ADIF. Este módulo é puro (sem I/O) e testado em
/// `test/logbook_test.dart`.
///
/// Formato de um campo: `<NOME:TAMANHO[:TIPO]>valor` — o TAMANHO é em **bytes** (UTF-8).
/// O cabeçalho termina em `<EOH>` e cada QSO termina em `<EOR>`.
library;

import 'dart:convert';

/// Um registro ADIF bruto: nome do campo (maiúsculas) -> valor.
typedef AdifRecord = Map<String, String>;

class Adif {
  const Adif._();

  /// Interpreta um texto ADIF e devolve os registros (QSOs). O cabeçalho é ignorado.
  ///
  /// Tolerante: ignora lixo entre campos e aceita campos em qualquer caixa (maiúsculas/minúsculas).
  static List<AdifRecord> parse(String text) {
    final bytes = utf8.encode(text);
    final records = <AdifRecord>[];
    var current = <String, String>{};
    var i = 0;
    // Se o texto tem <EOH>, tudo antes dele é cabeçalho e deve ser ignorado.
    var inHeader = _hasHeader(text);
    while (i < bytes.length) {
      if (bytes[i] != 0x3C) {
        // '<'
        i++;
        continue;
      }
      final close = bytes.indexOf(0x3E, i); // '>'
      if (close < 0) break;
      final tag = utf8.decode(bytes.sublist(i + 1, close), allowMalformed: true);
      final parts = tag.split(':');
      final name = parts[0].trim().toUpperCase();
      i = close + 1;
      if (name == 'EOH') {
        inHeader = false;
        current = <String, String>{};
        continue;
      }
      if (name == 'EOR') {
        if (!inHeader && current.isNotEmpty) records.add(current);
        current = <String, String>{};
        continue;
      }
      if (parts.length < 2) continue;
      final len = int.tryParse(parts[1].trim());
      if (len == null || len < 0 || i + len > bytes.length) continue;
      final value = utf8.decode(bytes.sublist(i, i + len), allowMalformed: true);
      i += len;
      if (!inHeader) current[name] = value;
    }
    return records;
  }

  static bool _hasHeader(String t) => RegExp(r'<eoh>', caseSensitive: false).hasMatch(t);

  /// Codifica um campo ADIF (vazio -> string vazia).
  static String field(String name, String? value) {
    if (value == null || value.isEmpty) return '';
    return '<$name:${utf8.encode(value).length}>$value ';
  }

  /// Cabeçalho ADIF com identificação do programa.
  static String header({String program = 'JTMobile', String version = '0.2.0'}) {
    final sb = StringBuffer()
      ..writeln('JTMobile ADIF export')
      ..write(field('ADIF_VER', '3.1.4'))
      ..write(field('PROGRAMID', program))
      ..write(field('PROGRAMVERSION', version))
      ..writeln('<EOH>');
    return sb.toString();
  }

  /// Serializa um registro (campos na ordem dada) terminando em `<EOR>`.
  static String serialize(AdifRecord r) {
    final sb = StringBuffer();
    r.forEach((k, v) => sb.write(field(k, v)));
    sb.writeln('<EOR>');
    return sb.toString();
  }
}
