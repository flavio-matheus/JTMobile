# JTDX para Android — estudo de viabilidade e arquitetura

Data: 2026-10-15 · Escopo: app Android (Flutter + NDK) para decodificar/transmitir FT8, FT4 e JT65, com rádio Icom IC-705 via Bluetooth.

## 1. Resumo executivo

| Pergunta | Resposta curta |
|---|---|
| Dá para fazer um app Android a partir do JTDX? | **Sim**, mas por portar o **código-fonte** (GPLv3), não por engenharia reversa do `.exe`. |
| Precisa do `rea` (engenharia reversa)? | **Não para o núcleo.** O JTDX é código aberto. O `rea` só faria sentido para auditar um binário sem fonte; além disso exige Ghidra/Hopper/IDA + Node 22+, que **não estão instalados** nesta máquina. |
| Dá para usar **só Bluetooth** com o IC-705? | **CI-V (controle/PTT) sim. Áudio digital não.** O Bluetooth do IC-705 expõe perfis HFP, HSP, SPP e GATT: o áudio é de voz (headset, banda estreita), inadequado para FT8. |
| Como levar o áudio do IC-705 ao celular? | **USB-C (OTG)**: placa de som USB interna do rádio (48 kHz) + CI-V — é o caminho mais documentado. **Wi-Fi**: o IC-705 tem servidor próprio compatível com o protocolo RS-BA1 (UDP 50001 controle / 50002 CI-V / 50003 áudio). |
| Licença do app resultante | **GPLv3** (obrigatório se derivar do JTDX/WSJT-X). |

**Arquitetura recomendada de conexão:** Bluetooth SPP para CI-V (frequência, modo, PTT) + **áudio por USB OTG ou Wi-Fi/RS-BA1**. Um modo "Bluetooth-only" real não é viável para decodificação confiável.

## 2. Sobre os arquivos anexados

- `JTDX ULTIMA VERSAO-2.2.160-rc7-win64.exe` (47 MB): instalador oficial, versão v2.2.160-rc7, copyright Igor Chernikov UA3DJY e Arvo Jarve ES1JA. Sem assinatura digital verificável.
- `JTDX.exe` (50 MB): sem metadados de versão; contém marcador **Nullsoft** (NSIS) e `UPX`, ou seja, parece **outro instalador/empacotado**, não o executável do programa. Não foi identificado nem executado. Hash SHA-256 de ambos foi calculado e está no histórico da sessão.
- Nenhum dos dois foi executado. Recomendo não rodar o `JTDX.exe` de origem desconhecida; compare com o instalador oficial.

## 3. Por que não engenharia reversa

1. **JTDX é GPLv3**, fork do WSJT-X, com fonte público (SourceForge `jtdx`, espelho no GitHub `jtdx-project/jtdx`). O fonte é infinitamente melhor que pseudocódigo descompilado de Fortran/C++/Qt.
2. O decodificador é **Fortran** (`jt9`, `lib/ft8`, `lib/jt65_decode.f90` etc.), compilado com gfortran: descompilar isso gera código quase ilegível.
3. O `rea` (MIT, MCP para agentes) delega a análise nativa a **Ghidra, Hopper ou IDA**. Nenhum está instalado (nem Java/Node).
4. Reimplementar os protocolos é público: FT8/FT4 são documentados pelo WSJT-X; JT65 é documentado por K1JT.

**Onde o `rea` ainda ajuda:** comparar o comportamento do binário com a sua reimplementação (ex.: vetores de teste de decodificação) ou analisar o APK de apps concorrentes. Posso configurá-lo se você quiser.

## 4. Os modos

| Modo | Janela | Modulação | Largura | Codificação | Observação |
|---|---|---|---|---|---|
| **FT8** | 15 s | 8-GFSK, 79 símbolos, 6,25 baud | ~50 Hz | LDPC(174,91)+CRC14 | Mais usado; relógio com erro < ~1 s |
| **FT4** | 7,5 s | 4-GFSK, 105 símbolos, 20,83 baud | ~83 Hz | LDPC(174,91)+CRC14 | Concursos |
| **JT65** | 60 s | 65-FSK, 126 símbolos, 2,69 baud | ~178 Hz | Reed-Solomon(63,12) | Decodificação por Koetter-Vardy (soft) é a parte pesada; EME/HF fraco |

Todos operam sobre áudio de 12 kHz (reamostrado dos 48 kHz do rádio), alinhados ao relógio UTC. **O relógio do celular precisa estar sincronizado (NTP/GPS)**; o app deve mostrar o desvio de tempo (DT).

## 5. IC-705: o que importa para o app

- **CI-V**: endereço padrão `A4h`. PTT, frequência, modo, DATA MOD e potência via comandos CI-V (ex.: `1C 00` para PTT).
- **USB**: o rádio aparece como placa de som USB (48 kHz) + porta serial CI-V (no Android, via USB Host/OTG).
- **Bluetooth**: perfis HFP/HSP/SPP/GATT; até 4 dispositivos pareados. SPP serve para CI-V ("CI-V Echo On/Off" no menu). Áudio via BT é voz.
- **Wi-Fi (servidor RS-BA1)**: UDP 50001/50002/50003, exige *Network control ON*, DATA MOD = WLAN; implementações abertas existem (`kappanhang`, `wfview`) e servem de referência do protocolo.
- Pontos a validar em campo: estabilidade do SPP no Android, latência do PTT, queda de BT, e atraso do áudio na TX.

## 6. Cenário Android — o que muda

- **Áudio**: `AAudio`/Oboe (NDK) com USB Audio Class; TX precisa gerar tons GFSK contínuos sem *underrun*.
- **USB/Bluetooth**: `UsbManager` + `BluetoothSocket` (SPP, permissão `BLUETOOTH_CONNECT`), Foreground Service para manter o ciclo de 15 s com tela apagada.
- **Fortran não roda no NDK moderno** (sem gfortran): portar para **C/C++** ou usar f2c/LFortran.
- **Bateria/CPU**: o JTDX usa decodificação multipasso/AP pesada; no celular, começar com ft8_lib (leve) e ir adicionando passes.

## 7. Arquitetura proposta

```
Flutter (UI: cascata, lista de decodes, QSO, log)
   │ dart:ffi / platform channels
Kotlin (camada de plataforma)
   ├─ UsbSerial / UAC (USB OTG)
   ├─ Bluetooth SPP (CI-V)
   └─ Foreground Service, NTP, permissões
C++ (NDK)
   ├─ ft8_lib (MIT)  → FT8 / FT4 encode+decode (base do MVP)
   ├─ jt65 (port de lib/jt65*.f90 → C++, incl. RS + KV)  → fase 2
   ├─ resampler 48k→12k, FFT, sync de slots
   └─ geração de tons GFSK (TX)
Camada de rádio: interface Rig {setFreq, setMode, ptt}; impl. CI-V (IC-705) via BT/USB/Wi-Fi
```

Existem apps Android abertos do mesmo gênero (FT8CN, MIT, FT8/FT4 com CI-V; qFT8) — vale estudar antes de reinventar. Eles **não** trazem JT65.

## 8. Plano em fases

1. **MVP (FT8 receber)**: Flutter + ft8_lib via FFI, áudio do celular/USB, cascata, lista de decodes.
2. **Rádio**: CI-V IC-705 por BT SPP (freq/modo/PTT) + áudio USB.
3. **TX FT8** + máquina de estados de QSO + log ADIF.
4. **FT4**.
5. **JT65** (port do Fortran, RS/KV).
6. **Wi-Fi/RS-BA1**, melhorias de decodificação (multipasso, AP), PSK Reporter.

## 9. Riscos

- Áudio via Bluetooth puro: não resolvido pelo rádio.
- Qualidade do decodificador vs JTDX (o JTDX é otimizado para HF; ft8_lib decodifica menos).
- Sincronismo de relógio e timing de TX em Android.
- Licença GPLv3 e crédito aos autores originais (K1JT, UA3DJY, ES1JA).
- Uso de radioamador exige licença; o app deve avisar sobre indicativo/limites de potência.

## 10. Fontes

- Perfis BT do IC-705: Icom America FAQ — https://icomamericasupport.zendesk.com/hc/en-us/articles/35050966822036-IC-705-Instructions-and-FAQs
- Servidor RS-BA1 / portas UDP: kappanhang — https://pkg.go.dev/github.com/nonoo/kappanhang
- ft8_lib (MIT): https://github.com/kgoba/ft8_lib
- FT8CN: https://github.com/N0BOY/FT8CN
- JTDX (GPLv3): pacote AUR https://aur.archlinux.org/packages/jtdx/ · jtdx_improved https://sourceforge.net/projects/jtdx-improved/
- REA: https://github.com/morluto/rea
