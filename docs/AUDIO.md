# Caminho de áudio, latência e temporização

**Requisito:** o áudio não pode ter atrasos, pois a decodificação vem pelo áudio. Este documento explica como o app
minimiza e **mede** atrasos, onde ainda existem e como calibrá-los.

## 1. Onde o atraso pode surgir

| Origem | Tamanho típico | Tratamento |
|---|---|---|
| Buffer interno do rádio (RX) | dezenas de ms | Não controlável; coberto pela calibração por DT (§5) |
| Rede Wi-Fi (jitter/perdas) | 1–50 ms, perdas ocasionais | `AudioTimeline` (§3) + reordenação com retransmissão (`_RxSeq`, 120 ms máx.) |
| Processamento no app | < 1 ms por pacote | Decimação nativa com buffers pré-alocados; decodificação em *isolate* |
| Jitter do app (GC, redesenho) | 5–30 ms | `AudioTimeline` (mínimo em janela deslizante) |
| Buffer de TX do rádio | `txBufferMs` (padrão 150 ms) | Configurável; `txAdvanceMs` compensa |
| Relógio do celular | ±centenas de ms | Compensação manual + **calibração pelo DT** |

FT8/FT4 toleram DT de até ±1 s (decodificam), mas DT próximo de 0 melhora a sensibilidade e a coerência entre estações.

## 2. Pipeline de RX (`Engine._onRxAudio`)
```
pacote 48 kHz ──▶ AudioTimeline.onChunk(chegada, n) ──▶ hora de captura (µs UTC) e amostras de preenchimento
              └─▶ decimador nativo (FIR 64 taps, 48→12 kHz) ──▶ _placeSamples(hora) ──▶ buffer do slot
                                                           └─▶ FFT → waterfall
```
* O **buffer do slot** (12 kHz, `slotSeconds × 12000` amostras) é preenchido **pela hora de captura**, não pela ordem de chegada.
  Lacunas viram zeros; se um pacote cruza a fronteira de slot, é dividido.
* A **decodificação** dispara quando o **áudio** do slot chega a `ModeSpec.decodeAtSeconds` (FT8: 14,0 s; FT4: 6,4 s) —
  independe do relógio de parede e do jitter.
* Durante a TX o RX não é gravado e o slot transmitido não é decodificado.

## 3. `AudioTimeline` (`lib/engine/audio_timeline.dart`)
* O rádio envia amostras a taxa constante ⇒ o tempo relativo entre amostras é exato (`k/48000`). Falta apenas o **offset absoluto**.
* Para cada pacote: `raw = chegada − (amostras_até_o_fim / taxa)` = offset **+ atraso daquele pacote**. O atraso nunca é negativo,
  então o **mínimo** numa janela de 10 s estima o offset verdadeiro + o atraso mínimo de rede.
* O offset segue o mínimo com *slew* limitado (150 µs/pacote) — absorve desvio de relógio (50 ppm testados) sem saltos; saltos > 150 ms reancoram.
* **Perdas:** se o atraso extra fica > 60 ms por 3 pacotes seguidos (persistente, ao contrário de jitter), insere-se silêncio
  equivalente ao atraso (`padSamples`) — o alinhamento é recuperado (testado com perda de 100 ms).
* Testes: `test/audio_timeline_test.dart` (jitter 0–30 ms, perda de 100 ms, deriva de 50 ppm).

Indicadores na interface: *Configurações → Áudio e temporização*: **jitter médio** e **lacunas preenchidas**; o cabeçalho mostra ping e pacotes perdidos.

## 4. TX
* Texto → tons (`ftx_encode`) → GFSK a **48 kHz** (`ftx_synth`) → PCM s16 com **0,5 s de silêncio** inicial (`ModeSpec.txStartOffset`).
* `_txStep` (20 ms) envia o PCM acompanhando o relógio do slot com folga de **120 ms** (evita *underrun*) + `txAdvanceMs`.
* O rádio recebe o áudio em um *jitter buffer* de `txBufferMs` (padrão **150 ms**; `IcomNetworkRadio.txBufferMs`; reconectar para aplicar).
  Menor ⇒ menos atraso, porém mais sensível a oscilações. O kappanhang relata que > ~500 ms impede a TX.
* `txAdvanceMs` (−300…+500 ms): antecipa (positivo) ou atrasa o envio. **Procedimento:** peça relatórios de DT de outros operadores
  (ou observe seu sinal em um SDR/WebSDR); se o DT ≈ +0,3 s, aumente o avanço em ~300 ms.
* PTT liga no início do slot; os 0,5 s iniciais de silêncio absorvem a latência do PTT.

## 5. Calibração pelo DT
`Engine.dtMedianSeconds` = mediana do DT de mensagens fortes (SNR > −12 dB) dos últimos slots.
* DT > 0 (sinais "atrasados") ⇒ nosso relógio está **adiantado** (ou o áudio chega com atraso).
* *Configurações → Calibrar relógio pelo DT* aplica `clockOffsetMs −= DT·1000` (`Engine.calibrateClockFromDt`).
* Ajuste fino exclusivo do RX: `rxLatencyMs` (desloca a hora de captura do áudio recebido).
* Idealmente sincronize o relógio do celular por rede/GPS antes de calibrar; ative "Data e hora automáticas" no Android para manter o relógio sincronizado pela rede.

## 6. Qualidade do áudio
* **Nível de RX:** o indicador "Áudio" mostra dBFS; alvo ≈ −35 a −15 dBFS de ruído. Verde = ok, âmbar = baixo, vermelho = saturação.
* **Nível de TX:** `Configurações → Nível de TX`; ajuste para ALC do rádio quase imóvel (use TUNE). Nunca sature o áudio.
* Decimação: passa-baixas FIR de 64 taps (corte 5 kHz) — banda de FT8/FT4 é < 3,2 kHz.

## 7. Ideias para reduzir ainda mais
* Preferir **USB-C/OTG** (áudio UAC) quando disponível: latência de poucos ms e sem perda de pacotes.
* Reduzir o tamanho do pacote de áudio (se o firmware permitir) e usar *foreground service* com prioridade alta de rede.
* Estimar `txAdvanceMs` automaticamente medindo o eco do próprio sinal (TX→RX) em loopback.
