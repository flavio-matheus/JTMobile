# Roadmap e pendências

Priorização sugerida (1 = mais urgente). Marque aqui o que for concluído e registre no `CHANGELOG.md`.

## P1 — Validação com hardware real (bloqueia o uso em campo)
- [ ] Conectar a um **IC-705 real** por Wi-Fi: login, abertura de fluxos, áudio RX contínuo, CI-V, PTT, TX.
- [ ] Medir **atraso de TX** e definir `txBufferMs`/`txAdvanceMs` padrão (usar DT relatado por outros operadores / WebSDR).
- [ ] Confirmar a escala de potência (`14 0A`) e o texto dos menus (README/PROTOCOLO) conforme o firmware.
- [ ] Verificar comportamento com tela apagada/ocupada e troca de rede.
- [ ] Documentar divergências do protocolo em `docs/PROTOCOLO_ICOM.md`.

## P2 — Qualidade de decodificação
- [ ] Decodificador de **maior sensibilidade**: multipasso, subtração de sinais, decodificação AP (a priori), "deep" estilo JTDX.
  Caminho: portar o decodificador FT8 do JTDX (GPLv3, Fortran→C/C++) ou estender a ft8_lib com subtração.
- [ ] SNR mais próximo do WSJT-X (hoje ±5 dB).
- [ ] Comparar sistematicamente com JTDX/WSJT-X usando gravações reais (script de regressão automatizado).

## P3 — Novos modos
- [ ] **JT65** (A/B/C): port do decodificador (Reed-Solomon + Koetter-Vardy) e do codificador; mensagens de 13 caracteres.
- [ ] **JT9**, depois **FST4/FST4W** e **WSPR** (RX → TX). Ver `docs/MODOS.md`.

## P4 — Logbook e serviços
- [ ] Tela de **importação ADIF** (arquivo) e mesclagem.
- [ ] Integrações (fase 2): **QRZ.com**, **LoTW (TQSL)**, **eQSL**, **Club Log**, **HRDLog** (`LogbookService`).
- [ ] Estatísticas (DXCC/grids/WAS), `cty.dat` completo (DXCC preciso, zonas CQ/ITU), mapa.
- [ ] Armazenamento seguro de credenciais (`flutter_secure_storage`).

## P5 — Operação e robustez
- [ ] **Serviço em primeiro plano** (operar com a tela apagada) + notificação persistente + **notificações do sistema** (hoje os alertas visuais/sonoros só funcionam com o app aberto; veja docs/SIMULADOR.md).
- [ ] Sincronização de hora (NTP/GPS) com indicação de erro; calibração automática opcional pelo DT.
- [ ] Reconexão inteligente (mudança de rede), diagnósticos de rede (RTT, perdas) na UI.
- [ ] **PSK Reporter** (envio de spots), alertas (sons) para CQ de países novos / chamadas para mim.
- [ ] Split/VFO A-B, RIT, AGC/NR sincronizados.
- [ ] Outros transportes: **USB-OTG** (áudio UAC + CI-V serial), **Bluetooth SPP** para CI-V (o áudio BT do IC-705 é voz — não serve para dados), outros rádios (Yaesu/Kenwood/Xiegu).
- [ ] Tablet/landscape refinado, acessibilidade, internacionalização (hoje só PT-BR).

## P6 — Projeto
- [ ] CI (GitHub Actions): `flutter analyze`, `flutter test`, build do APK.
- [ ] Testes de widget/golden da UI; teste instrumentado do decodificador no emulador.
- [ ] Renomear `applicationId` e pacote Kotlin para o definitivo; ícone e nome finais; assinatura *release*.
- [ ] Capturas de tela no README.

## Dívidas técnicas conhecidas
* `Engine` concentra muita responsabilidade (áudio, slots, TX, QSO, log): avaliar dividir em `RxPipeline`, `TxController`, `QsoController`.
* `Decode`/`ParsedMessage` não tratam mensagens de campo (contest) e textos livres de 13 caracteres de JT65.
* Tabela DXCC por prefixo é aproximada (`core/dxcc.dart`).
* A interface do waterfall desenha a imagem inteira a cada quadro (suficiente hoje; otimizar com atualização incremental).
