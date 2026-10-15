# Simulador, alertas e guia de operação

O JTMobile traz um **simulador de rádio** para treinar o fluxo completo de um QSO sem hardware — e o mesmo guia/alertas
funcionam com o IC-705 real. Este documento explica **como interagir**, **o que o simulador faz** e **como os alertas funcionam**.

## 1. Como fazer um QSO completo no simulador (passo a passo)

1. *Configurações → Tipo de conexão → Simulador* (é o padrão na primeira execução). Informe seu indicativo e grid.
2. Na aba **Atividade**, as linhas **verdes com "CQ"** são estações chamando (K1ABC e EA3XYZ chamam CQ o tempo todo, com sinal forte).
3. Toque no ícone **↩ (responder)** de uma delas. O app:
   * seleciona a estação, escolhe o **período de TX oposto** ao dela e **arma o TX** (como o duplo clique do WSJT-X);
   * mostra o alerta azul *"Respondendo a K1ABC — TX armado…"* e o **guia** com a contagem até a sua transmissão.
4. No seu período o app **transmite** → alerta **vermelho** + bip + vibração (*"Transmitindo K1ABC PY2XYZ GG66"*).
5. No período seguinte a estação **responde** → alerta **verde** + acorde de 3 notas + vibração (*"K1ABC respondeu! PY2XYZ K1ABC -08"*).
6. O app continua **sozinho** (auto-sequência): relatório → R-relatório → RR73 → 73. Cada resposta gera novo alerta.
7. Ao concluir: alerta **dourado** + arpejo (*"QSO completo com K1ABC!"*) e o diálogo **Registrar QSO**. Confirme e veja em **Logbook** (ícone do livro).

**Chamar CQ geral:** toque **Chamar CQ** no guia (ou *Meu QSO / TX → CQ* e **Ativar TX**). Uma estação responde com o grid dela e o
app conduz o resto. **HALT** interrompe tudo a qualquer momento.

### Roteiros simulados (`lib/engine/sim_script.dart`)
**A — você responde a um CQ**
```
você: K1ABC PY2XYZ GG66     (Tx1)
ele:  PY2XYZ K1ABC -08
você: K1ABC PY2XYZ R-03     (Tx3, automático)
ele:  PY2XYZ K1ABC RR73     → QSO completo (registro)
você: K1ABC PY2XYZ 73       (Tx5, automático)
```
**B — você chama CQ**
```
você: CQ PY2XYZ GG66        (Tx6)
ele:  PY2XYZ K1ABC FN42
você: K1ABC PY2XYZ -04      (Tx2, automático)
ele:  PY2XYZ K1ABC R-09
você: K1ABC PY2XYZ RR73     (Tx4, automático)
ele:  PY2XYZ K1ABC 73       → QSO completo, sem mais transmissões
```
Estações inexistentes e o seu 73 final não recebem resposta (como na vida real). Os roteiros são **testados**
(`test/sim_qso_test.dart`) com o mesmo `QsoManager` usado no app.

### Tempo
Cada ciclo FT8 dura 15 s. Seu TX ocorre a cada **30 s** (mesmo período), com a resposta no período intermediário; um QSO completo
leva ≈ 1,5–2,5 min. Troque o período de TX em *Meu QSO / TX → Transmitir no 1º/2º slot*.

## 2. O guia na tela (`CoachBanner`, `lib/ui/guidance.dart`)
A faixa colorida acima da waterfall diz **o que está acontecendo e qual é o próximo passo**, com botão de ação:

| Situação | Guia | Botão |
|---|---|---|
| Rádio desconectado | "Rádio desconectado — toque no selo…" | Conectar |
| Nenhuma estação selecionada | "Como falar com alguém? Toque em ↩ numa chamada CQ…" | Chamar CQ |
| Estação selecionada, TX desligado | "K1ABC selecionada — toque ATIVAR TX: o app envia '…' no 2º período (em 8 s)" | Ativar TX |
| TX armado | "QSO com K1ABC: enviando seu grid. Próxima TX em 12 s (tentativa 1)…" | Parar |
| Transmitindo | "TRANSMITINDO agora" + mensagem | HALT |
| QSO concluído | "QSO completo com K1ABC! Foi para o Logbook…" | Chamar CQ |

O ícone **?** no topo reabre o tutorial *Seu primeiro QSO* (exibido na primeira execução).

## 3. Alertas (`lib/engine/alerts.dart`)
| Evento | Faixa | Som | Vibração |
|---|---|---|---|
| Você começa a **transmitir** | vermelha "Transmitindo" | bip descendente curto | 1 pulso |
| Uma estação **responde / chama você** | verde "K1ABC respondeu!" | acorde ascendente de 3 notas | 3 pulsos |
| **QSO completo** | dourada | arpejo de dó maior | 4 pulsos |
| Orientações (responder, selecionar) | azul | tom curto | 1 pulso curto |

* Além da faixa, a **borda da tela pisca** na cor do alerta (visível de relance).
* Uma faixa de *resposta/QSO completo* fica **≥ 3,5 s** na tela mesmo que o TX comece logo em seguida.
* Os sons são **sintetizados no código** (`AlertSounds`), tocados via `AudioTrack` no volume de **mídia** — ajuste-o antes de operar.
* Liga/desliga o som no ícone de alto-falante do topo; vibração e "responder arma o TX" em *Configurações → Alertas e guia*;
  botão **Testar alertas** nas configurações.
* **Limitação:** os alertas só aparecem com o app aberto (tela ligada — o app mantém a tela acesa). Notificações do sistema com o app
  em segundo plano/tela apagada dependem do *foreground service* (veja [ROADMAP.md](ROADMAP.md) P5).

## 4. Como o simulador gera o sinal
`SimRadio` produz áudio de 48 kHz (ruído + sinais FT8/FT4 **reais**, codificados pela mesma biblioteca nativa) alinhado ao relógio UTC.
* Estações "alwaysCq" transmitem CQ em todo período; as demais conversam aleatoriamente entre si.
* Quando o PTT do usuário é solto, `simReplyTo(mensagem enviada)` decide a resposta, que é **colocada no próximo período**, na
  frequência da estação e com sinal suficientemente forte (≥ −8 dB) para sempre decodificar.
* `SimRadio.radioSideChange(...)` simula mudanças feitas no painel do rádio (teste da sincronização).

## 5. Estendendo
* **Nova estação / comportamento:** edite `kSimStations` e `simReplyTo` em `sim_script.dart` e acrescente casos em `test/sim_qso_test.dart`.
* **Novo alerta:** inclua um `AlertKind`, notas em `AlertSounds.notes`, padrão em `NativeAlertPlayer._patterns` e cor/ícone em `guidance.dart`.
* **Novo passo do guia:** `CoachBanner._state()` em `guidance.dart` (ordem = prioridade).
