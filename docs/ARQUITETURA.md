# Arquitetura do JTMobile

Este documento descreve **como o app está organizado e por quê**, para que qualquer pessoa (ou IA) consiga
manter e evoluir o projeto. Leia junto com `README.md` e, para temas específicos, os demais arquivos em `docs/`.

## 1. Visão em camadas

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ UI (Flutter)               lib/ui/*       telas, waterfall, diálogos         │
├──────────────────────────────────────────────────────────────────────────────┤
│ Motor (Dart)               lib/engine/*   Engine, QsoManager, RadioSync,     │
│                                           AudioTimeline, WaterfallBuffer     │
├───────────────────────┬───────────────────────────────┬──────────────────────┤
│ Rádio (Dart)          │ Núcleo de sinal (C via FFI)    │ Logbook (Dart)       │
│ lib/radio/*           │ android/.../cpp/ftx_bridge.c   │ lib/logbook/*        │
│ RadioLink (interface) │ + ft8_lib (MIT)                │ ADIF, QsoLog         │
│ IcomNetworkRadio      │ decode/encode/synth/FFT/dec4   │ LogbookService (f.2) │
│ SimRadio (engine/)    │ lib/core/ftx_native.dart       │                      │
├───────────────────────┴───────────────────────────────┴──────────────────────┤
│ Android nativo (Kotlin)   MainActivity.kt: bindWifi (fixa o app ao Wi-Fi)    │
└──────────────────────────────────────────────────────────────────────────────┘
```

Regra de dependência: **UI → Engine → {Radio, Core, Logbook}**. O motor não conhece widgets; a UI só observa o
`Engine` (`ChangeNotifier`) e dois `ValueNotifier` de alta frequência (`wfTick`, `clockTick`). `Radio`, `Core` e
`Logbook` não dependem do motor.

## 2. Módulos

### 2.1 `lib/radio/` — enlace com o rádio
* **`radio_link.dart`** — interface `RadioLink`: estado (`RadioState`), fluxo de áudio de RX (`rxAudio`, PCM s16le mono 48 kHz),
  comandos (`setFrequency`, `setUsbData`, `setMode`, `setRfPower`, `setPtt`, `sendTxAudio`, `requestState`...).
  **Todo novo rádio/transporte implementa esta interface.**
* **`icom_link.dart`** — `IcomNetworkRadio`: protocolo de rede da Icom (UDP). Ver [PROTOCOLO_ICOM.md](PROTOCOLO_ICOM.md).
* **`civ.dart`** — CI-V puro (sem I/O): construção de comandos, parsing de quadros, `RadioState`, BCD.
* **`passcode.dart`** — codificação de usuário/senha do login Icom.
* `lib/engine/sim_radio.dart` — `SimRadio`: simulador (áudio com ruído + sinais FT8/FT4 reais; responde às chamadas).

### 2.2 `lib/engine/` — motor
* **`engine.dart`** — orquestração: ciclo de slots, pipeline de áudio de RX, decodificação, TX, QSO, logbook, sincronização.
* **`audio_timeline.dart`** — hora de captura do áudio imune a jitter; detecta perdas. Ver [AUDIO.md](AUDIO.md).
* **`radio_sync.dart`** — sincronização bidirecional. Ver [SINCRONIZACAO.md](SINCRONIZACAO.md).
* **`qso.dart`** — sequenciador Tx1..Tx6 / auto-sequência (lógica pura).
* **`waterfall.dart`** — buffer circular de linhas de espectro, AGC e conversão para imagem.
* **`alerts.dart`** — `AlertCenter` (faixa/flash/som/vibração), `AlertSounds` (sons sintetizados) e `NativeAlertPlayer` (canal nativo). Ver [SIMULADOR.md](SIMULADOR.md).
* **`audio_monitor.dart`** — `AudioMonitor`: espelha o áudio de RX no alto-falante do celular (canal nativo `monitor`).
* **`sim_script.dart`** — roteiro das estações simuladas (`simReplyTo`), lógica pura testada.
* `debug_wav.dart` — ferramenta de depuração (somente *debug*): decodifica WAVs de um diretório do app.

### 2.3 `lib/core/` — núcleo compartilhado
* **`ftx_native.dart`** — FFI para `libftx_bridge.so` e a interface `FtxCodec` (substituível em testes).
* **`modes.dart`** — catálogo de modos (`ModeSpec`) e bandas/frequências (`Band`). Ver [MODOS.md](MODOS.md).
* **`models.dart`** — `ParsedMessage` e `Decode` (mensagem + país, distância, azimute, flags).
* `dxcc.dart` (país por prefixo), `geo.dart` (Maidenhead, distância/azimute), `settings.dart` (SharedPreferences).

### 2.4 `lib/logbook/`
`adif.dart` (leitor/escritor ADIF), `qso_record.dart` (modelo + status por serviço), `qso_log.dart` (persistência,
consultas, exportação), `log_services.dart` (interface das integrações online — fase 2). Ver [LOGBOOK.md](LOGBOOK.md).

### 2.5 `lib/ui/`
`home_page.dart` (layout retrato/paisagem), `guidance.dart` (alertas na tela, guia contextual, tutorial), `status_header.dart`, `waterfall_view.dart`, `activity_list.dart`,
`qso_panel.dart`, `station_sheet.dart`, `radio_sheet.dart`, `log_page.dart`, `settings_page.dart`, `theme.dart`.

### 2.6 Código nativo (`app/android/app/src/main/cpp/`)
`ftx_bridge.c` expõe (via `dart:ffi`) as funções abaixo; `CMakeLists.txt` compila o bridge com a **ft8_lib** (MIT).

| Função | Papel |
|---|---|
| `ftx_decode(samples, n, rate, protocolo, fmin, fmax, max, out)` | Decodifica um slot (FT8/FT4): candidatos, LDPC, CRC, SNR (ref. 2500 Hz), DT, frequência |
| `ftx_encode(texto, protocolo, tons)` | Mensagem → tons (79 FT8 / 105 FT4) |
| `ftx_synth(tons, protocolo, f0, rate, sinal)` | Tons → áudio GFSK (BT 2,0 FT8 / 1,0 FT4) com rampa de envelope |
| `ftx_spectrum(amostras, nfft, saida_db)` | FFT (Hann) em dB para a waterfall |
| `ftx_dec4_new/free/ftx_dec4` | Decimador 48→12 kHz (FIR 64 taps, buffer circular) |

A tabela de indicativos com *hash* (para mensagens `<...>`) é mantida em memória estática da biblioteca.

## 3. Fluxos principais

### 3.1 Recepção
1. `IcomNetworkRadio` entrega `Int16List` (≈20 ms) em `rxAudio`.
2. `Engine._onRxAudio`: `AudioTimeline.onChunk` → hora de captura; decimador nativo → 12 kHz; nível RMS.
3. `_placeSamples`: grava no buffer do slot pela **hora de captura**; lacunas viram silêncio.
4. Quando o **áudio** do slot atinge `ModeSpec.decodeAtSeconds`, `_runDecode` chama `codec.decodeAsync` (isolate separado).
5. Resultados viram `Decode`s; a auto-sequência reage à mensagem dirigida a mim; a UI é notificada.
6. Em paralelo, `_feedSpectrum` alimenta a waterfall (FFT 4096 pontos a cada ~150 ms).

### 3.2 Transmissão
1. `_tick` (20 ms, relógio UTC) detecta o início do slot de TX configurado (`txParity`).
2. `_startTx`: `QsoManager.currentMessage` → `ftx_encode` → `ftx_synth` (48 kHz) → PCM com 0,5 s de silêncio inicial.
3. PTT ligado por CI-V; `_txStep` (20 ms) envia o áudio acompanhando o relógio do slot (+120 ms de folga + `txAdvanceMs`).
4. Ao fim, PTT desligado; após Tx5 (73) o QSO é encerrado e o log é oferecido/gravado.

### 3.3 Sincronização com o rádio
`RadioSync` compara o `RadioState` com o último valor visto e com as escritas recentes do app. Mudanças originadas
**no rádio** viram `RadioChange` → `Engine._onRadioChange` (ex.: ajusta a banda); escritas do app (`push*`) enviam o CI-V
e abrem uma janela de guarda. Detalhes: [SINCRONIZACAO.md](SINCRONIZACAO.md).

## 4. Decisões de projeto (e alternativas descartadas)

| Decisão | Motivo | Alternativas |
|---|---|---|
| Flutter + núcleo C via FFI | UI rápida de escrever, DSP nativo e portátil | Kotlin puro (mais código de UI); Fortran do JTDX (NDK moderno não tem gfortran) |
| **Não** fazer engenharia reversa do `.exe` do JTDX | JTDX é GPLv3 com fonte; o decodificador é Fortran (ilegível descompilado) | Ghidra/REA só seriam úteis para auditar binários sem fonte |
| ft8_lib (MIT) no MVP | Pequena, portátil, comprovada em microcontroladores | Port do decodificador do JTDX (maior sensibilidade) — no roadmap |
| Wi-Fi/UDP (protocolo Icom) em vez de Bluetooth | O Bluetooth do IC-705 expõe HFP/HSP/SPP/GATT: áudio só de voz (banda estreita) | BT SPP para CI-V + USB-OTG para áudio (opção futura) |
| Decodificar em *isolate* | Não travar a UI (decodificação de dezenas de ms) | `compute` por chamada |
| Sample-clock (AudioTimeline) | DT estável mesmo com jitter/GC | Hora de chegada do pacote (impreciso) |
| Logbook em ADIF puro | Formato universal; um arquivo legível; compatível com todos os serviços | SQLite (mais pesado; ADIF seria só exportação) |
| `ChangeNotifier` sem pacote de estado | Menos dependências, suficiente para este tamanho | Riverpod/Bloc |

## 5. Como estender

* **Novo rádio/transporte:** implemente `RadioLink` (CI-V reaproveita `civ.dart`); selecione em `Engine.connectRadio` e `RadioKind`.
* **Novo modo digital:** veja [MODOS.md](MODOS.md#como-adicionar-um-novo-modo).
* **Nova integração de logbook:** implemente `LogbookService` (veja [LOGBOOK.md](LOGBOOK.md)).
* **Novo parâmetro sincronizável:** acrescente ao `RadioState`, aos comandos em `civ.dart`, a `SyncField` e aos `push*`/`_emit` em `radio_sync.dart`.

## 6. Convenções de código

* Comentários e documentação em **português**; identificadores em inglês/português técnico já estabelecido.
* Cada arquivo começa com um comentário `///` + `library;` explicando seu papel.
* Lógica pura (CI-V, ADIF, QSO, AudioTimeline, RadioSync) **sem I/O** e com testes unitários.
* Sem acentos em scripts PowerShell que reescrevem arquivos (use as ferramentas de edição de arquivo; veja `DESENVOLVIMENTO.md`).
