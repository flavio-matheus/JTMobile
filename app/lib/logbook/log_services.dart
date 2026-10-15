/// Interface das integrações de logbook online (FASE 2 — ainda não implementadas).
///
/// Cada serviço (QRZ.com, LoTW, eQSL, Club Log, HRDLog...) implementará [LogbookService]. O app
/// chamará [LogbookService.upload] com os QSOs ainda não enviados (`uploadStatus != 'Y'`) e, em
/// caso de sucesso, `QsoLog.markUploaded`. O status por serviço já é gravado no ADIF, então o log
/// atual continua válido quando as integrações chegarem.
///
/// Notas de projeto por serviço (detalhes em `docs/LOGBOOK.md`):
///  * **QRZ.com**: API REST `logbook.qrz.com/api` (`ACTION=INSERT`, chave de API do logbook; ADIF
///    no corpo). Precisa de assinatura XML para consultas, mas o envio usa só a chave do logbook.
///  * **LoTW**: exige QSOs **assinados** com certificado pessoal pelo TQSL (gera `.tq8`). Opções:
///    exportar ADIF e abrir no TQSL, ou implementar a assinatura (PKCS#12) — avaliar legalmente.
///  * **eQSL**: upload HTTP (`ImportADIF.cfm`) com usuário/senha.
///  * **Club Log**: API `realtime.php` com e-mail, senha de aplicativo e *API key* do desenvolvedor.
///  * **HRDLog**: API `NewEntry.aspx` com código de upload.
/// Credenciais devem ficar em armazenamento seguro (ex.: `flutter_secure_storage`) — nunca no ADIF.
library;

import 'qso_record.dart';

/// Resultado de um envio.
class UploadResult {
  const UploadResult({required this.accepted, this.rejected = const [], this.message = ''});

  /// Ids (`QsoRecord.id`) aceitos pelo serviço.
  final List<String> accepted;

  /// Ids rejeitados (duplicados, dados inválidos...).
  final List<String> rejected;

  /// Mensagem do serviço (para exibir ao usuário).
  final String message;
}

/// Contrato de um serviço de logbook online.
abstract class LogbookService {
  /// Qual serviço este objeto representa.
  LogService get service;

  /// `true` se as credenciais necessárias estão configuradas.
  bool get configured;

  /// Envia [records] ao serviço. Deve lançar exceção em falhas de rede/autenticação.
  Future<UploadResult> upload(List<QsoRecord> records);
}

/// Serviços previstos, com o estado de implementação (para a tela de configurações).
const List<({LogService service, bool implemented, String note})> kPlannedLogServices = [
  (service: LogService.qrz, implemented: false, note: 'Chave de API do logbook; envio de ADIF por HTTPS.'),
  (service: LogService.lotw, implemented: false, note: 'Requer assinatura TQSL (certificado). Por ora: exporte o ADIF.'),
  (service: LogService.eqsl, implemented: false, note: 'Usuário/senha do eQSL.cc.'),
  (service: LogService.clublog, implemented: false, note: 'E-mail, senha de aplicativo e API key.'),
  (service: LogService.hrdlog, implemented: false, note: 'Código de upload do HRDLog.net.'),
];
