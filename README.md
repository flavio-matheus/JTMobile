# FT Mobile — FT8/FT4 para Android com IC-705 via Wi-Fi

Aplicativo Android (Flutter + núcleo nativo em C) para operar modos digitais com o **Icom IC-705 sem fio**,
usando o mesmo protocolo de rede do aplicativo **RS-MS1A** (UDP 50001/50002/50003: login, CI-V e áudio).
Não é um port do JTDX: é uma implementação nova, de código aberto, inspirada na operação do JTDX/WSJT-X.
(Veja `JTDX-Android-Estudo.md` para o estudo de viabilidade e por que não foi feita engenharia reversa do `.exe`.)

## O que já funciona (testado)

| Área | Estado | Como foi verificado |
|---|---|---|
| Decodificação FT8/FT4 (ft8_lib, MIT) | OK | Gravações de referência do WSJT-X rodando no emulador Android x86_64: mesmas mensagens e frequências (±2 Hz) nos sinais mais fortes; decodifica 4–17 msgs/slot em 20–90 ms |
| Estimativa de DT | OK (calibrada) | Bate com o WSJT-X nas gravações de referência (±0,1 s) |
| Estimativa de SNR | Aproximada | Erro típico de ±5 dB frente ao WSJT-X (ele satura em sinais fortes) |
| Codificação/síntese FT8/FT4 + TX | OK em simulador | Sequência de QSO completa contra estações simuladas; TX com PTT, medidores PO/SWR |
| Waterfall | OK | Zoom por pinça (300–3200 Hz), 4 atalhos de largura, **modo Dial TX** (deslizar o espectro sob a mira define a frequência de TX), modo Explorar, etiquetas de indicativos sobre os sinais, linhas de slot |
| Auto-sequência QSO (Tx1–Tx6), log ADIF | OK (testes unitários) | `flutter test` |
| Cliente de rede Icom (login, CI-V, áudio RX/TX) | OK contra "rádio falso" | `test/icom_link_test.dart` reimplementa o servidor conforme o protocolo de referência (kappanhang, MIT) |
| **Conexão real com o IC-705** | **NÃO TESTADA** | Não havia rádio disponível. Pode haver diferenças de firmware; veja "Próximos passos" |

## Interface (pensada para celular)

* **Cabeçalho**: estado do enlace (Wi-Fi/ping/pacotes perdidos), frequência de dial, modo (USB-D), FT8/FT4,
  relógio UTC com compensação, barra de progresso do slot (1º/2º), indicador RX/TX com a mensagem em transmissão,
  S-meter (RX) ou PO/SWR (TX), nível de áudio (dBFS) com cor de alerta, nº de decodificações e tempo de decodificação, chips de banda.
* **Waterfall**: marcadores Rx (verde) e Tx (vermelho) com a largura do sinal; mira central no modo Dial; barra de posição na faixa 0–3200 Hz.
* **Atividade** (equivalente à *Band Activity*): UTC, SNR, DT, frequência, mensagem; filtros Todas / CQ / Para mim / Perto do Rx;
  etiquetas CQ, PARA MIM, JÁ TRAB., NOVO PAÍS; país/continente, distância e azimute. Toque = ficha completa da estação; “Responder” = inicia QSO.
* **Meu QSO / TX**: estação (DX, grid, país, distância, relatórios), mensagens Tx1–Tx6, slot de TX (1º/2º), auto-sequência,
  manter frequência de TX, CQ, registrar QSO. Barra inferior: Ativar TX, HALT, TUNE, Log (exportação ADIF).

## Como configurar o IC-705 (igual ao RS-MS1A)

1. No rádio: *Network control* = ON (WLAN › Remote), cadastre **Network User1** (usuário/senha) e use-os no app.
2. Portas UDP padrão 50001/50002/50003. Configure `DATA MOD = WLAN`.
3. Conecte o celular ao Wi-Fi do rádio (modo Access Point; IP típico `192.168.200.1`) e, no app, toque em
   **Vincular app ao Wi-Fi do rádio** (o Wi-Fi do rádio não tem internet e o Android tentaria usar o 4G/5G).
4. Feche o RS-MS1A/JTDX no PC enquanto usa o app: o rádio atende **um** cliente de rede por vez.

## Compilar

```
cd app
flutter pub get
flutter build apk --release --split-per-abi
```
Requisitos: Flutter, Android SDK + NDK (CMake 3.22). Em Windows, se o Gradle falhar com
`Unable to establish loopback connection`, defina `TEMP`/`TMP` para uma pasta curta (ex.: `C:\tmp_b`) e `JAVA_HOME` para o JBR do Android Studio.

## Estrutura

```
app/lib/radio/      protocolo Icom UDP (icom_link.dart), CI-V (civ.dart), enlace abstrato (radio_link.dart)
app/lib/engine/     motor: slots, áudio, waterfall, decodificação, TX, QSO, log; simulador de rádio (sim_radio.dart)
app/lib/core/       FFI (ftx_native.dart), mensagens FT8, DXCC por prefixo, geodésia, configurações
app/lib/ui/         telas e waterfall interativa
app/android/app/src/main/cpp/   ponte C (ftx_bridge.c) + ft8_lib (MIT)
app/test/           testes unitários e teste do protocolo de rede
```

## Limitações conhecidas e próximos passos

1. **Teste com o IC-705 real** (prioridade): validar login, estabilidade do áudio UDP, latência/atraso de TX (ajuste de `txDelay`) e
   o comportamento de PTT por CI-V. O código segue o protocolo documentado pelo kappanhang, mas não foi exercitado com hardware.
2. **Sensibilidade do decodificador**: a ft8_lib é de passe único. O JTDX/WSJT-X decodificam mais sinais fracos (multi-passes, subtração
   de sinais, decodificação AP). Próxima etapa: portar o decodificador do JTDX (GPLv3) para C/C++ ou adicionar passes de subtração.
3. **JT65 e outros modos** (JT9, FST4, MSK144) não implementados. JT65 exige portar o decodificador Reed-Solomon/Koetter-Vardy do Fortran.
4. **Serviço em primeiro plano**: hoje o app mantém a tela ligada (wake lock). Para operar com a tela apagada é preciso um *foreground service*.
5. **DXCC**: tabela compacta por prefixo (não é o `cty.dat` completo); “NOVO PAÍS” só compara com o log local.
6. Relógio: usa o do celular (ajuste manual em ms). Sincronismo NTP/GPS não implementado.
7. PSK Reporter, ADIF import, TX em frequência dividida e Hold de DX call ainda não existem.

## Licença e créditos

Código do app: use GPLv3 (compatível com o JTDX/WSJT-X caso você incorpore o decodificador deles).
Incorpora `ft8_lib` (MIT, Karlis Goba) e usa o protocolo descrito pelo `kappanhang` (MIT, HA2NON/ES1AKOS).
O uso para transmissão exige licença de radioamador e respeito aos limites de potência/banda do seu país.
