# Sincronização app ↔ rádio

**Requisito:** o app deve ler as configurações, frequências e ajustes do rádio, e o rádio deve receber os do app;
os dois permanecem sincronizados. Implementação: `lib/engine/radio_sync.dart` (+ `Engine`, `civ.dart`, `icom_link.dart`).

## 1. Parâmetros sincronizados

| Parâmetro (`SyncField`) | Leitura (rádio → app) | Escrita (app → rádio) | Onde aparece no app |
|---|---|---|---|
| `frequency` | `03` (poll 1 s) / notificação `00` | `05` | Cabeçalho, painel do rádio, seleção de banda |
| `mode` + `filter` | `04` (poll 2 s) / notificação `01` | `06` | Cabeçalho, painel do rádio, aviso "use USB-D" |
| `dataMode` | `1A 06` (poll 2 s) | `1A 06` | idem |
| `rfPower` | `14 0A` (poll 4 s) | `14 0A` | Painel do rádio (controle deslizante em %) |
| `preamp` | `16 02` | `16 02` | Painel do rádio |
| `att` | `11` | `11` | Painel do rádio |

Medidores (S, PO, SWR) são só leitura e vêm a cada 250 ms. Com o **CI-V Transceive** ligado no rádio, frequência e modo
chegam instantaneamente por notificação.

## 2. Regras (`RadioSync`)

1. **Escrita do app** (`pushFrequency`, `pushMode`, `pushUsbData`, `pushRfPower`...): envia o CI-V, registra o valor
   pedido e abre uma **janela de guarda** (2,5 s por padrão) para aquele campo.
2. **Leitura do rádio** (`onLinkChanged`, a cada notificação do enlace): compara com o último valor visto.
   * Dentro da janela de guarda e valor ≠ pedido → é **resposta atrasada** de um polling anterior → **ignorada**
     (impede que o valor "pule de volta" depois de o usuário alterar).
   * Valor igual ao pedido → é o **eco** da própria escrita → ignorado.
   * Fora da janela e valor diferente → o usuário mexeu **no rádio** → gera `RadioChange` → `Engine._onRadioChange`.
3. O `IcomNetworkRadio` atualiza o `state` **de forma otimista** ao escrever (a UI reage na hora); a leitura confirma.

## 3. Ao conectar (`Engine._initialSync`)
1. `requestState()` lê frequência, modo, DATA, potência, pré-amp e ATT (espera até 3 s pelas respostas básicas).
2. Política (`Settings.syncPolicy`):
   * **`radioFirst` (padrão):** `adoptAll()` — o app adota o que está no rádio (a banda do app passa a ser a do rádio).
   * **`appFirst`:** o app envia sua frequência padrão (modo/banda escolhidos) ao rádio.
3. Se `autoFixMode` e o rádio não estiver em USB-D → `pushUsbData()`.

## 4. Reflexos na interface
* Mudou a frequência no rádio → a **banda** do app acompanha (`Engine._onRadioChange`) e o cabeçalho mostra a nova frequência.
* Rádio fora de **USB-D** → faixa âmbar com botão **Corrigir** (`Engine.fixRadioMode`).
* Frequência diferente do padrão do modo/banda (>100 Hz) → faixa com botão **Ir** (`goToStandardSetup`).
* **Painel do rádio** (toque na frequência): frequência (digitar kHz), modo, **potência em %**, pré-amp, ATT, "Sincronizar agora".
* Mudar **banda** ou **modo** no app envia a frequência padrão correspondente (`kBands[i].dialFor(mode)`).

## 5. Como adicionar um parâmetro
1. Campo em `RadioState` (`civ.dart`), comando de leitura/escrita e tratamento em `Civ.apply`.
2. Valor em `SyncField` e ramos em `RadioSync.adoptAll/onLinkChanged/push*`.
3. Método na interface `RadioLink` e nas implementações (`IcomNetworkRadio`, `SimRadio`, `FakeLink` nos testes).
4. Inclua o comando de leitura no rodízio de `_pollTickFn` e em `requestState`.
5. Teste em `test/radio_sync_test.dart` e resposta correspondente no servidor falso de `test/icom_link_test.dart`.

## 6. Limitações conhecidas
* Polling de 1–4 s sem transceive; uma mudança simultânea no app e no rádio dentro da janela de guarda prevalece a do app.
* Split, VFO A/B, RIT/XIT, AGC e NR não são sincronizados (acrescente conforme a necessidade).
* A escala de `rfPower` (0–255) é mapeada em 0–100 %; a potência em watts do log é aproximada (10 W máx. do IC-705).
