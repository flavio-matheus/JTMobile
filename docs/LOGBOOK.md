# Logbook

## 1. O que existe hoje (fase 1)

* **Armazenamento:** um arquivo **ADIF 3.1.4** (`jtmobile_logbook.adi`) na pasta de documentos do app (`getApplicationDocumentsDirectory`).
  `QsoLog.load()` lê o arquivo ao iniciar; inclusões fazem *append*; edição/exclusão reescrevem de forma **atômica** (arquivo
  temporário + renomear).
* **Registro de QSO:** ao concluir um contato (RR73/73) o motor cria um rascunho (`Engine.pendingLog`) e a interface abre o
  diálogo **Registrar QSO** (indicativo, grid, modo, RST enviado/recebido, frequência, nome, comentário). Em *Configurações → Logbook*
  é possível **registrar sem perguntar**. Também há o botão **Registrar QSO** no painel do QSO (manual).
* **Tela Logbook:** busca (indicativo/nome/grid/banda/modo), editar (toque), excluir (arrastar), exportar **ADIF** e **CSV**
  (folha de compartilhamento do Android: e-mail, Drive, apps de log…), lista de integrações previstas.
* **Consultas:** `isWorked(call, band, mode)` (dupe-check), países trabalhados (para o selo **NOVO PAÍS**), "JÁ TRAB." na lista de atividade.
* **Importação:** `QsoLog.importAdif(texto)` funde registros de outro programa descartando duplicados (mesmo indicativo, banda, modo e ±5 min).
  (A interface de importação ainda não existe; a função está pronta e testada.)

### Campos ADIF gravados
`CALL, QSO_DATE, TIME_ON, QSO_DATE_OFF, TIME_OFF, BAND, FREQ, MODE (+SUBMODE), RST_SENT, RST_RCVD, GRIDSQUARE, NAME, COMMENT,
STATION_CALLSIGN, MY_GRIDSQUARE, TX_PWR` + qualquer campo desconhecido encontrado na importação (preservado em `QsoRecord.extra`).
`FT4` é gravado como `MODE=MFSK` + `SUBMODE=FT4` (padrão ADIF).

### Status de envio por serviço (já gravado)
| Serviço | Campo ADIF | Valores |
|---|---|---|
| QRZ.com | `QRZCOM_QSO_UPLOAD_STATUS` | Y / N / M |
| LoTW | `LOTW_QSL_SENT` | Y / N / R / Q |
| eQSL | `EQSL_QSL_SENT` | Y / N / R / Q |
| Club Log | `CLUBLOG_QSO_UPLOAD_STATUS` | Y / N / M |
| HRDLog | `HRDLOG_QSO_UPLOAD_STATUS` | Y / N / M |

Assim o log atual já é compatível com as integrações: `QsoLog.markUploaded(serviço, ids)` grava "Y" no ADIF.

## 2. Fase 2 — integrações online (a implementar)

Interface (`lib/logbook/log_services.dart`):
```dart
abstract class LogbookService {
  LogService get service;
  bool get configured;                          // credenciais presentes
  Future<UploadResult> upload(List<QsoRecord>); // lança em erro de rede/autenticação
}
```
Fluxo desejado: tela **Integrações** (credenciais em armazenamento seguro, ex. `flutter_secure_storage`), botão **Enviar pendentes**
(QSOs com `uploadStatus != 'Y'`), envio automático opcional após cada QSO, tratamento de duplicados/erros e `markUploaded`.

> As notas abaixo são **pontos de partida**; confirme sempre a documentação oficial atual de cada serviço antes de implementar.

| Serviço | Abordagem sugerida | Observações |
|---|---|---|
| **QRZ.com** | API do Logbook (HTTPS; `ACTION=INSERT`, ADIF no corpo, **chave de API do logbook**) | Requer assinatura XML no QRZ para algumas funções de consulta; o envio usa a chave do logbook |
| **LoTW (ARRL)** | QSOs precisam ser **assinados** com o certificado do operador pelo **TQSL** (gera `.tq8`) e enviados ao LoTW | Opção A (rápida): exportar o ADIF e abrir no TQSL. Opção B: implementar a assinatura (PKCS#12/X.509 do LoTW) — avaliar segurança e requisitos da ARRL |
| **eQSL.cc** | Upload HTTP (`ImportADIF.cfm`) com usuário/senha e ADIF | Verifique políticas de uso da API |
| **Club Log** | API de upload (e-mail, senha de aplicativo e **API key** do aplicativo) | A *API key* é emitida ao desenvolvedor do app (solicitar ao Club Log) |
| **HRDLog.net** | `NewEntry.aspx` com código de upload | — |

Boas práticas: nunca registrar credenciais no ADIF/Git; mostrar ao usuário o que será enviado; respeitar limites de taxa;
registrar erros por QSO; permitir reenvio.

## 3. Importação/exportação com outros programas
* **JTDX/WSJT-X:** `wsjtx_log.adi` pode ser importado via `QsoLog.importAdif`.
* **Exportar:** Logbook → Exportar ADIF; importe em LoTW (via TQSL), QRZ, eQSL, Club Log ou qualquer log (Log4OM, N1MM, HAMRS…).

## 4. Evoluções previstas
* Tela de importação de arquivo ADIF; mesclagem com confirmação.
* Mapa/estatísticas (DXCC, grids, WAS), filtros por banda/modo/data.
* Confirmações (QSL) recebidas de LoTW/QRZ.
* `cty.dat` completo para DXCC preciso.
