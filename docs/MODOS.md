# Modos digitais (FT8 / FT4 / JT65 / JT9 / …)

O catálogo de modos fica em `app/lib/core/modes.dart` (`kModes`, `ModeSpec`) e as frequências por banda em `kBands`
(`Band.dial`). A interface (seletor de modo no cabeçalho) e o motor consultam apenas esse catálogo: **os parâmetros de tempo
vêm do modo, não de constantes espalhadas**.

## 1. Situação

| Modo | Período | Largura | Estado | Observações |
|---|---|---|---|---|
| **FT8** | 15 s | ~50 Hz | ✅ RX + TX | ft8_lib; LDPC(174,91)+CRC14; 79 símbolos; tons 6,25 Hz |
| **FT4** | 7,5 s | ~83 Hz | ✅ RX + TX | 105 símbolos; tons 20,83 Hz |
| **JT65** | 60 s | ~178 Hz | ⏳ planejado | Reed-Solomon(63,12), 126 símbolos, 65 tons; decodificação Koetter-Vardy (soft) é a parte pesada |
| **JT9** | 60 s | ~16 Hz | ⏳ planejado | convolucional K=32 + FEC; 85 símbolos |
| **FST4** | 15–1800 s | 25 Hz+ | ⏳ planejado | LDPC; para baixas frequências/sinais fracos |
| **WSPR** | 120 s | 6 Hz | ⏳ planejado (só RX) | balizas; sem QSO estruturado (`structuredQso: false`) |

Modos não implementados aparecem **desabilitados** no seletor com a descrição "(em desenvolvimento)"; `Engine.setMode` recusa
selecioná-los com um aviso.

## 2. O que define um modo (`ModeSpec`)

| Campo | Uso |
|---|---|
| `slotSeconds` | Período T/R; define o slot, o tamanho do buffer de áudio e a barra de progresso |
| `txStartOffset` | Silêncio inicial do áudio de TX (FT8/FT4: 0,5 s; JT65/JT9: 1,0 s) |
| `decodeAtSeconds` | Instante (no **áudio** do slot) em que a decodificação dispara |
| `toneSpacingHz`, `bandwidthHz` | Largura dos marcadores Rx/Tx na waterfall |
| `ftx` | Codec nativo (FT8/FT4) — `null` para modos ainda sem codec |
| `implemented` | Habilita seleção, decodificação e TX |
| `structuredQso` | Usa Tx1..Tx6/auto-sequência (WSPR: não) |

Frequências: `Band.dial['FT8']` etc. Bandas sem frequência padrão para um modo simplesmente não movem o rádio.
⚠️ Confira as frequências de dial nos planos de banda oficiais (ex.: WSJT-X) antes de operar.

## 3. Como adicionar um novo modo

1. **Catálogo** — acrescente um `ModeSpec` em `kModes` (deixe `implemented: false` até o codec existir) e as frequências em `kBands`.
2. **Codec** — implemente em C/C++ (preferível, NDK) ou Dart:
   * `decode(samples12k, …) → List<RawDecode>` (texto, SNR, DT, frequência);
   * `encode(texto) → símbolos/tons` e `synth(...) → áudio` (taxa 48 kHz para TX);
   * mantenha a interface `FtxCodec` (ou generalize-a: ex.: `ModeCodec` com `id`) e registre no `FtxNative`/fábrica de codecs.
   O JT65 exige portar do Fortran do WSJT-X/JTDX (`jt65_decode`, `sfrsd` etc.) para C — o NDK moderno **não** possui gfortran.
3. **Motor** — `Engine._runDecode/_startTx` usam `protocol` (FT8/FT4). Para outras famílias, selecione o codec pelo `ModeSpec.family`
   (ex.: `codecFor(mode)`), e ajuste `AudioTimeline`/buffer (já usam `slotSeconds` do modo).
4. **Mensagens** — `ParsedMessage` (core/models.dart) interpreta o formato FT8/FT4; JT65/JT9 usam mensagens de 13 caracteres com
   campos similares (indicativo, grid, relatório). Estenda o parser conforme o modo.
5. **Logbook** — `QsoRecord.toAdif` mapeia `FT4 → MODE=MFSK/SUBMODE=FT4`; os demais usam o próprio id (JT65, JT9, FST4, WSPR são modos ADIF válidos).
6. **Testes** — adicione gravações de referência (WAV 12 kHz + saída esperada do WSJT-X/JTDX) e compare com `debugDecodeWavFiles`
   (veja [DESENVOLVIMENTO.md](DESENVOLVIMENTO.md#depuração-de-decodificação-com-wavs)). Atualize `test/modes_test.dart`.
7. **Documentação** — marque o modo como implementado aqui e no `README.md`/`ROADMAP.md`.

## 4. Notas por modo

### JT65 (próximo alvo)
* 60 s; sinal começa em 1,0 s; 126 símbolos (63 de dados + sincronismo), tons espaçados de 2,6917 Hz (65 valores), submodos A/B/C (largura ×1/×2/×4).
* Decodificação: sincronismo por correlação → demodulação soft → Reed-Solomon (63,12) por Koetter-Vardy (`sfrsd` no WSJT-X; fallback `bmdec`/hard).
* A JTDX/WSJT-X são GPLv3: o port para C é permitido mantendo a licença (este projeto é GPLv3).
* Referência de validação: `jt65code`/`jt65sim` do WSJT-X geram sinais de teste.

### JT9
* 60 s, 85 símbolos, 9 tons de 1,736 Hz, FEC convolucional (r=1/2, K=32) com decodificação sequencial (Fano). Mensagens de 13 caracteres (mesmo `pack` do JT65).

### FST4/FST4W
* Períodos de 15 s a 1800 s; LDPC(240,101). Requer sincronismo robusto; útil em 2200 m/630 m.

### WSPR
* 120 s; mensagens 50 bits; decodificação por Fano; só RX no início (envia spots em fase futura).

## 5. Dinâmica de comunicação por modo
O ciclo **RX → decodifica → auto-sequência → TX → …** é o mesmo em todos os modos de QSO estruturado: o `Engine` usa
`ModeSpec.slotSeconds` para calcular o slot, `txParity` para escolher o período de TX, `decodeAtSeconds` para disparar a decodificação
e `txStartOffset` para alinhar a transmissão. Modos longos (60 s) exigem pouca mudança além do codec e das mensagens.
