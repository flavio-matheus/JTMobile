# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/). Versão ainda em **alfa** (0.x).

## [0.2.0] — em desenvolvimento
### Adicionado
- **Catálogo de modos** (`core/modes.dart`): FT8 e FT4 implementados; JT65, JT9, FST4 e WSPR registrados como "em desenvolvimento".
  Seletor de modo no cabeçalho; bandas com limites e frequências de dial por modo.
- **Sincronização bidirecional app ↔ rádio** (`engine/radio_sync.dart`): frequência, modo/DATA/filtro, potência de RF, pré-amp e ATT;
  janela de guarda contra eco/respostas atrasadas; política ao conectar (rádio ou app); avisos de modo/frequência fora do padrão;
  **painel do rádio** (toque na frequência).
- **Áudio de baixa latência**: `AudioTimeline` (hora de captura imune a jitter, preenchimento de perdas), decodificação disparada
  pelo áudio, decimador nativo com buffer circular e buffers pré-alocados, `txBufferMs`/`txAdvanceMs`/`rxLatencyMs`,
  indicadores de jitter, **calibração do relógio pelo DT**.
- **Logbook persistente em ADIF** (`logbook/`): leitura/escrita UTF-8, edição, exclusão, busca, dupe-check, importação de ADIF,
  exportação ADIF/CSV, diálogo "Registrar QSO", status de envio por serviço (LoTW/QRZ/eQSL/Club Log/HRDLog) e interface `LogbookService` (fase 2).
- Documentação ampla (`docs/`), `AGENTS.md`, `CONTRIBUTING.md`, licença **GPL-3.0**, script `tools/install.ps1`.
- Testes: modos, `RadioSync`, `AudioTimeline`, logbook/ADIF e leitura de ajustes CI-V no servidor Icom falso (41 testes no total).
### Alterado
- Nome do projeto: **JTMobile** (rótulo do app e documentação). Pacote Dart `jtmobile`.
- Buffer de áudio de TX solicitado ao rádio: 300 → **150 ms** (configurável).
- Comentários de código ampliados em todos os módulos.

## [0.1.0] — versão inicial
- FT8/FT4 (decodificação e TX) com ft8_lib via FFI; waterfall interativa (zoom, *Dial TX*); lista de atividade e ficha da estação;
  QSO automático; cliente do protocolo de rede Icom (IC-705 via Wi-Fi); simulador de rádio; log ADIF básico; testes e APK.
