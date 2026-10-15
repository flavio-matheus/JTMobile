# Protocolo de rede da Icom (RS-BA1 / RS-MS1A) e CI-V

O IC-705 (e outros rádios Icom com servidor de rede embutido) fala o protocolo UDP usado pelos aplicativos
**RS-BA1** (PC) e **RS-MS1A** (Android). Este projeto o reimplementa em Dart (`lib/radio/icom_link.dart`) com base no
estudo do projeto aberto **kappanhang** (MIT, https://github.com/nonoo/kappanhang). Não há documentação oficial pública;
tudo aqui vem da análise do kappanhang e de testes com um servidor falso (`test/icom_link_test.dart`).

> ⚠️ **Não foi validado com um IC-705 real.** Se algo divergir (firmware), compare com a captura do tráfego do RS-MS1A/kappanhang.

## 1. Três fluxos UDP

| Fluxo | Porta (rádio) | Função |
|---|---|---|
| Controle | 50001 | Handshake, login, autenticação, abertura dos fluxos serial/áudio, reautenticação |
| Serial | 50002 | Quadros **CI-V** (comandos e respostas) encapsulados |
| Áudio | 50003 | Áudio PCM 16 bit **mono 48 kHz** (RX do rádio e TX para o rádio) |

Cada fluxo usa um *socket* UDP próprio. `SID local` = `(IP[2] << 24) | (IP[3] << 16) | porta_local`; o `SID remoto`
é informado pelo rádio no handshake.

## 2. Cabeçalho de 16 bytes (todos os pacotes)

```
 0..3   comprimento total do pacote (uint32, little-endian)
 4..5   tipo (uint16 LE): 0x00 dados/idle · 0x01 pedido de retransmissão · 0x03 "are you there"
        0x04 "I am here" · 0x05 desconectar · 0x06 "are you ready" · 0x07 ping
 6..7   número de sequência (uint16 LE)
 8..11  SID de quem envia (uint32, big-endian)
 12..15 SID de quem recebe (uint32, big-endian)
```

## 3. Handshake de cada fluxo (`_UdpStream.handshake`)
1. Cliente envia **pkt3** (×2); rádio responde **pkt4** com seu SID (bytes 8..11).
2. Cliente envia **pkt6** (×2, seq=1); rádio responde **pkt6**.

## 4. Sequência de conexão (`IcomNetworkRadio._session`)
1. Handshake no fluxo de **controle**.
2. **Login** (pacote de 128 bytes): usuário e senha codificados por `icomPasscode` (tabela de substituição, 16 bytes cada) e a
   string `icom-pc`. Resposta de 96 bytes; `r[48..51] == FF FF FF FE` = usuário/senha inválidos. `r[26..31]` = *authID*.
3. Início dos **pings** (pkt7, a cada 3 s) e envio de **auth** (64 bytes) com magic `0x02`, depois `0x05`.
4. Rádio envia o pacote de **capacidades** (168 bytes, `0xA8`): `r[66..82]` é o identificador exigido no próximo passo.
5. Cliente envia o **pedido de fluxos** (144 bytes, `0x90`): nome do rádio (`IC-705`), usuário codificado, parâmetros de
   áudio (**48000 Hz**, PCM 16 bit mono), portas serial/áudio e **buffer de TX em ms** (`txBufferMs`).
6. Rádio responde (144 bytes, `r[96]==1`) → abre-se o fluxo **serial** (com *open* `0xC0`) e o de **áudio**.
7. A cada 60 s repete-se **auth `0x05`** (reautenticação). Ao desconectar: pkt5 em cada fluxo e auth `0x01`.

## 5. Confiabilidade sobre UDP
* **pkt0 rastreado**: pacotes de dados enviados guardam-se em histórico (`_txHist`, ~600) para atender pedidos de
  retransmissão do rádio (`0x10 .. 01 00` para 1 pacote; `0x18 .. 01 00` para faixas). Se não houver, responde-se com *idle* daquela sequência.
* **Idle periódico**: a cada 100 ms (ou 1 s ocioso) para manter a sequência.
* **Recepção ordenada** (`_RxSeq`): reordena por sequência, pede retransmissão dos pacotes faltantes e, após 120 ms, desiste e
  segue (contabiliza perda em `lostPackets`). O áudio perdido é compensado por `AudioTimeline` ([AUDIO.md](AUDIO.md)).
* **Ping/latência**: medida no fluxo de controle e exibida no cabeçalho.

## 6. Serial (CI-V)
Pacote de dados: comprimento `0x15 + n`; `r[16] = 0xC1`, `r[17] = n`, `r[19..20]` = contador do serial (big-endian),
`r[21..]` = quadro CI-V (≤ 80 bytes por pacote).

### Quadro CI-V
`FE FE <destino> <origem> <comando> [subcomando] [dados] FD` — IC-705: `0xA4`; app: `0xE0`.

| Função | Comando |
|---|---|
| Ler/definir frequência | `03` / `05 <5 bytes BCD, LSB primeiro>` |
| Ler/definir modo | `04` / `06 <modo> <filtro>` (0 LSB, 1 USB, 2 AM, 3 CW, 4 RTTY, 5 FM) |
| DATA | `1A 06 <0/1> <filtro>` |
| PTT | `1C 00 <0/1>` ; TUNE `1C 01 <0/2>` |
| Potência de RF | `14 0A <BCD2 0000–0255>` |
| Pré-amplificador | `16 02 <0/1/2>` |
| Atenuador | `11 <00/20>` |
| Medidores | S `15 02` · PO `15 11` · SWR `15 12` · ALC `15 13` (BCD2, 0000–0255) |

`civ.dart` implementa tudo isto e tem testes em `test/core_test.dart`. Notificações espontâneas (`00` frequência, `01` modo)
chegam quando o **CI-V Transceive** está ligado no rádio.

## 7. Áudio
* Cada 20 ms de áudio = 1920 bytes = 960 amostras s16le, divididos em **dois pacotes**: `0x056C` (1388 B: 24 de cabeçalho + 1364) e
  `0x0244` (580 B: 24 + 556). O cabeçalho adiciona `r[16]=0x80`, contador de áudio (big-endian) em `r[18..19]` e tamanho do PCM em `r[22..23]`.
* **RX**: pacotes `0x056C/0x0244` chegam em sequência (`r[6..7]`) e alimentam `_RxSeq`.
* **TX**: o app envia nos mesmos formatos, em tempo real. O rádio usa o buffer pedido (`txBufferMs`) como *jitter buffer*;
  valores > ~500 ms impedem a TX (observação do kappanhang). Padrão do app: **150 ms** (configurável).

## 8. Requisitos de rede no Android
* O Wi-Fi do IC-705 não tem internet: o Android pode preferir o 4G/5G. `MainActivity.bindWifi` usa
  `ConnectivityManager.bindProcessToNetwork` para fixar o processo na rede Wi-Fi (botão "Vincular app ao Wi-Fi do rádio").
* Permissões: `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `WAKE_LOCK`.
* O rádio aceita **um** cliente de rede por vez (feche RS-MS1A/JTDX).

## 9. Como depurar / validar com hardware
1. Ative `debugIcom` em `icom_link.dart` (reintroduza logs por pacote) ou capture o tráfego com Wireshark (filtro `udp.port in {50001,50002,50003}`).
2. Compare o login/auth com uma sessão do RS-MS1A; os tamanhos de pacote (`0x80`, `0x60`, `0x40`, `0xA8`, `0x90`) são a referência.
3. Registre divergências neste arquivo.
