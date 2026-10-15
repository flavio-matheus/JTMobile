# Avisos de terceiros

O JTMobile é distribuído sob **GPL-3.0** (veja `LICENSE`). Ele incorpora ou depende dos componentes abaixo, cada um sob sua licença.

## Incorporados no repositório

### ft8_lib
* Autor: Karlis Goba (YL3JG) e colaboradores — https://github.com/kgoba/ft8_lib
* Licença: **MIT**
* Onde: `app/android/app/src/main/cpp/ft8lib/` (cópia de `ft8/`, `common/` sem `audio.*`, `fft/`; inclui `LICENSE`).
* Uso: codificação/decodificação FT8/FT4, LDPC, CRC, empacotamento de mensagens; FFT (KISS FFT, licença BSD incluída nos arquivos).

### KISS FFT (dentro da ft8_lib)
* Autor: Mark Borgerding — licença **BSD-3-Clause** (texto nos cabeçalhos de `ft8lib/fft/`).

## Referência (código não copiado; protocolo reimplementado)

### kappanhang
* Autores: HA2NON (Norbert Varga) e ES1AKOS (Akos Marton) — https://github.com/nonoo/kappanhang — licença **MIT**.
* Uso: o protocolo de rede Icom (`lib/radio/icom_link.dart`, `passcode.dart`) foi reimplementado em Dart a partir da análise deste projeto.
  A tabela de codificação de senha em `passcode.dart` e as estruturas de pacote seguem o kappanhang.

### Protocolos FT8 / FT4 / JT65 / JT9
* Joe Taylor (K1JT), Steve Franke (K9AN), Bill Somerville (G4WJS) e colaboradores — WSJT-X (GPL-3.0) — https://wsjt.sourceforge.io/
* A especificação dos protocolos é pública. Nenhum código do WSJT-X foi copiado até o momento.

### JTDX
* Igor Chernikov (UA3DJY), Arvo Järve (ES1JA) e colaboradores — GPL-3.0 — https://sourceforge.net/projects/jtdx-improved/
* Inspiração de interface e funções. Nenhum código do JTDX foi copiado até o momento; o roadmap prevê portar seu decodificador (GPL-3.0, compatível).

## Dependências Flutter/Dart (via `pubspec.yaml`)
`ffi`, `shared_preferences`, `path_provider`, `wakelock_plus`, `share_plus` e o próprio Flutter SDK — licenças BSD-3-Clause/MIT/Apache-2.0
(consulte o `pubspec.lock` e a licença de cada pacote).

## Marcas
"Icom", "IC-705", "RS-MS1A", "RS-BA1" são marcas de seus titulares. "WSJT-X" e "JTDX" são projetos independentes.
O JTMobile **não é afiliado** a nenhum deles.
