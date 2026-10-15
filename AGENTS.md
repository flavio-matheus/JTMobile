# AGENTS.md — guia para assistentes de IA (e pessoas) que trabalham no JTMobile

Leia este arquivo primeiro. Ele resume **o que é o projeto, onde está cada coisa, como validar mudanças e o que evitar**.

## O que é
App Android (Flutter + núcleo C via FFI) para modos digitais de HF (FT8/FT4 hoje; JT65/JT9… planejados) com o **Icom IC-705 via Wi-Fi**
(protocolo de rede da Icom, o mesmo do RS-MS1A). Licença **GPL-3.0**. Idioma de comentários e documentação: **português (BR)**.

## Mapa rápido
| Preciso mexer em… | Arquivo |
|---|---|
| Fluxo geral (áudio→decodifica→TX→QSO→log) | `app/lib/engine/engine.dart` |
| Protocolo de rede Icom | `app/lib/radio/icom_link.dart` (+ `docs/PROTOCOLO_ICOM.md`) |
| Comandos/respostas CI-V | `app/lib/radio/civ.dart` |
| Sincronização app↔rádio | `app/lib/engine/radio_sync.dart` (+ `docs/SINCRONIZACAO.md`) |
| Latência/hora de captura do áudio | `app/lib/engine/audio_timeline.dart` (+ `docs/AUDIO.md`) |
| Modos e frequências por banda | `app/lib/core/modes.dart` (+ `docs/MODOS.md`) |
| Decodificador/codificador/FFT nativos | `app/android/app/src/main/cpp/ftx_bridge.c` e `app/lib/core/ftx_native.dart` |
| Sequência de QSO (Tx1…Tx6) | `app/lib/engine/qso.dart` |
| Logbook/ADIF | `app/lib/logbook/*` (+ `docs/LOGBOOK.md`) |
| Telas | `app/lib/ui/*` |
| Simulador de rádio e roteiros das estações | `app/lib/engine/sim_radio.dart`, `sim_script.dart` (+ `docs/SIMULADOR.md`) |
| Alertas (som/visual/vibração) e guia na tela | `app/lib/engine/alerts.dart`, `app/lib/ui/guidance.dart` |

Arquitetura completa: `docs/ARQUITETURA.md`. Pendências: `docs/ROADMAP.md`.

## Como validar (sempre antes de concluir uma tarefa)
```powershell
cd app
flutter analyze      # precisa terminar com "No issues found!"
flutter test         # todos os testes devem passar (54 hoje)
```
* Mudou protocolo/CI-V/sync/áudio/logbook/modos? **Adicione/atualize testes** (`app/test/`). Lógica pura não deve fazer I/O.
* Mudou o código C ou a UI? Gere o APK (`flutter build apk --debug --target-platform android-x64`) e teste no emulador/aparelho
  (veja `docs/DESENVOLVIMENTO.md` para o fluxo e as armadilhas do Windows).
* O decodificador só roda no Android: valide com WAVs de referência via `debugDecodeWavFiles`.

## Regras do projeto
1. **Honestidade sobre o que foi testado.** Não declare funcionando com o IC-705 real: isso **ainda não foi validado**. Marque o que é inferido.
2. **Comentários em português**, cada arquivo com `///` + `library;` no topo, funções públicas documentadas. Explique o *porquê*, não só o *o quê*.
3. **Não faça engenharia reversa do `.exe` do JTDX**: o JTDX é GPLv3 com código-fonte; use o fonte. (Ver `docs/ESTUDO_VIABILIDADE.md`.)
4. **Licenças:** código novo é GPL-3.0. Ao incorporar código de terceiros, confira a licença e registre em `THIRD_PARTY_NOTICES.md`.
5. **Segurança:** nunca versionar credenciais, *keystores*, `.env`, senhas de rádio ou chaves de API. Credenciais de integrações vão para armazenamento seguro.
6. **Transmissão:** qualquer mudança que afete TX/PTT/potência exige cuidado extra (PTT travado, potência). O botão **HALT** e `Engine.stopTx` devem sempre soltar o PTT.
7. **Arquivos grandes/binários** (APKs, builds) **não** vão para o Git (`.gitignore`).
8. **Commits:** mensagens em português no formato `tipo(escopo): resumo` (ex.: `feat(sync): ...`, `fix(audio): ...`, `docs: ...`). Commits do projeto **não** levam coautoria de assistentes.

## Armadilhas conhecidas
* Windows: Gradle falha com `Unable to establish loopback connection` se `TEMP` for longo/8.3 → use `TEMP=C:\tmp_b`.
* PowerShell 5.1 corrompe acentos ao reescrever arquivos (leitura ANSI): edite com ferramentas que preservam UTF-8.
* `flutter test` roda no PC: `FtxNative.tryLoad()` devolve `null` fora do Android; a UI/engine usam um codec falso nos testes.
* O rádio atende **um** cliente de rede por vez (feche RS-MS1A/JTDX durante os testes).
* A hora usada nos slots é `Engine.now()` (UTC + `clockOffsetMs`); não use `DateTime.now()` direto para temporização de slots.

## Fluxo de trabalho sugerido
1. Leia o documento do tema em `docs/`.
2. Escreva/ajuste o teste que descreve o comportamento desejado.
3. Implemente; mantenha a lógica pura separada de I/O.
4. `flutter analyze` + `flutter test`; teste no emulador se tocou UI/nativo.
5. Atualize a documentação (`docs/`, `README.md`, `CHANGELOG.md`) e faça commit(s) pequenos e descritivos.
