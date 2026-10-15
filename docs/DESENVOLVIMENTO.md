# Guia de desenvolvimento

## 1. Pré-requisitos
* **Flutter** (testado com Dart 3.13 / Flutter estável recente) — `flutter doctor` sem pendências de Android.
* **Android SDK** + **NDK** (testado com NDK 28.2) + **CMake 3.22.1** (SDK Manager).
* **JDK 17+** (o JBR do Android Studio serve; defina `JAVA_HOME`).
* Git. (Opcional) um celular Android com depuração USB, ou um AVD.

## 2. Comandos do dia a dia
```powershell
cd app
flutter pub get
flutter analyze            # deve terminar com "No issues found!"
flutter test               # 41 testes (unitários + protocolo de rede)
flutter build apk --release --split-per-abi    # APKs por ABI em build/app/outputs/flutter-apk/
flutter build apk --debug --target-platform android-x64   # rápido, para o emulador x86_64
```
Os APKs **não** são versionados (`.gitignore`). Para distribuir, copie-os para `dist/` com o nome `JTMobile-<abi>.apk`.

## 3. Instalar no celular
```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r "C:\JTDX_Mobile\dist\JTMobile-arm64-v8a.apk"
# ou: powershell -ExecutionPolicy Bypass -File .\tools\install.ps1 -Apk "C:\JTDX_Mobile\dist\JTMobile-arm64-v8a.apk"
```
ADB sem fio (Android 11+): *Opções do desenvolvedor → Depuração sem fio → Parear* e `adb pair <ip:porta>` / `adb connect <ip:porta>`.

## 4. Problemas conhecidos no Windows
| Sintoma | Causa/solução |
|---|---|
| Gradle: `java.io.IOException: Unable to establish loopback connection` | O Java usa um socket UNIX em `TEMP`; com caminhos longos/8.3 falha. Defina `TEMP`/`TMP` para uma pasta **curta** (ex.: `C:\tmp_b`) e `JAVA_HOME` para o JBR: `$env:TEMP="C:\tmp_b"; $env:TMP="C:\tmp_b"; $env:JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"` |
| `git clone` falha com `'$GIT_DIR' too big` | Caminho de trabalho muito longo; clone em pasta curta (ex.: `C:\ref`) |
| Build do Android em pasta muito profunda | Mantenha o projeto em caminho curto (ex.: `C:\JTDX_Mobile`) |
| Scripts PowerShell 5.1 corrompem acentos ao reescrever arquivos | Não use `Get-Content/Set-Content` para editar `.dart` com acentos; use um editor/ferramenta que preserve UTF-8 (ou `[IO.File]::ReadAllText(p,[Text.Encoding]::UTF8)` e escrita UTF-8 sem BOM) |
| Emulador não aparece no `adb devices` | Inicie com `-no-window -gpu guest -no-audio -no-snapshot` (GPU do host pode travar); aguarde o boot (`sys.boot_completed`) |
| `adb exec-out screencap` gera PNG inválido no PowerShell | Use `adb shell screencap -p /sdcard/s.png` + `adb pull` |

## 4.1 Credenciais para `git push`
O `git push` usa o Git Credential Manager. Em terminais sem interação defina `GCM_INTERACTIVE=auto` e `GIT_TERMINAL_PROMPT=1`
para permitir o login via navegador na primeira vez.

## 5. Testes
| Arquivo | Cobre |
|---|---|
| `test/core_test.dart` | CI-V (BCD, quadros, medidores), passcode, mensagens FT8, geodésia/DXCC, `QsoManager` |
| `test/icom_link_test.dart` | `IcomNetworkRadio` completo contra um **servidor Icom falso** (handshake, login, auth, abertura de fluxos, CI-V, leitura de ajustes, áudio RX/TX) e falha com mensagem clara |
| `test/radio_sync_test.dart` | `RadioSync`: adoção, mudança no rádio, eco, resposta atrasada, janela de guarda |
| `test/audio_timeline_test.dart` | `AudioTimeline`: jitter, perda de 100 ms, deriva de relógio |
| `test/modes_test.dart` | Catálogo de modos e bandas |
| `test/logbook_test.dart` | ADIF (UTF-8), `QsoRecord`, `QsoLog` (persistência, dupes, importação, CSV, status de serviços) |

O decodificador nativo **não** roda no PC (é uma biblioteca Android). Ele é validado no emulador/aparelho com WAVs de referência (§6).
Não há testes de widget; a UI é verificada manualmente (emulador/aparelho).

## 6. Depuração de decodificação com WAVs
Em builds *debug*, `debugDecodeWavFiles` (`lib/engine/debug_wav.dart`) decodifica arquivos `*.wav` (PCM16 mono **12 kHz**, 15 s) em
`/sdcard/Android/data/br.poinsp.ft_mobile/files/wavtest/` e grava `<arquivo>.wav.out` com `SNR DT Freq ~ mensagem`.
```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb install -r app\build\app\outputs\flutter-apk\app-debug.apk
& $adb shell am start -n br.poinsp.ft_mobile/.MainActivity       # cria a pasta wavtest
& $adb push gravacao.wav /sdcard/Android/data/br.poinsp.ft_mobile/files/wavtest/
& $adb shell am force-stop br.poinsp.ft_mobile; & $adb shell am start -n br.poinsp.ft_mobile/.MainActivity
& $adb shell cat /sdcard/Android/data/br.poinsp.ft_mobile/files/wavtest/gravacao.wav.out
```
Gravações de referência com a saída do WSJT-X: `https://github.com/kgoba/ft8_lib/tree/master/test/wav`
(resultado atual: ver tabela em `README.md`).

## 7. Simulador de rádio
*Configurações → Tipo de conexão → Simulador* (padrão na 1ª execução). Gera ruído + 8 estações FT8/FT4 reais, responde ao CQ
(estação `PY2SIM`) e permite testar QSO/TX/logbook sem hardware. `SimRadio.radioSideChange(...)` simula mudanças feitas no painel do rádio.
Para pré-configurar indicativo/grid num build *debug* sem digitar: escreva `shared_prefs/FlutterSharedPreferences.xml` via `adb shell run-as br.poinsp.ft_mobile`
(chaves `flutter.callsign`, `flutter.grid`).

## 8. Código nativo
* Fontes: `app/android/app/src/main/cpp/` (`ftx_bridge.c`, `CMakeLists.txt`, `ft8lib/` = cópia da ft8_lib MIT).
* Ao alterar o C, recompile o APK (o Gradle chama o CMake). Para checar só a compilação: use o `clang` do NDK
  (`ndk/<versão>/toolchains/llvm/prebuilt/windows-x86_64/bin/x86_64-linux-android26-clang.cmd`).
* As funções exportadas têm `FTX_EXPORT`; os *bindings* estão em `lib/core/ftx_native.dart` (mantenha as assinaturas em sincronia).
* Atualizar a ft8_lib: substitua `ft8lib/{ft8,common,fft}` (sem `audio.c/h`) e registre em `THIRD_PARTY_NOTICES.md`.

## 9. Publicação (futuro)
* Assine com *keystore* própria (**nunca** versionar `*.jks`/`key.properties`); hoje o *release* usa a chave de debug.
* Altere o `applicationId` (hoje `br.poinsp.ft_mobile`) ao publicar numa loja (exige renomear pacote Kotlin e o canal `br.poinsp.ft_mobile/net`).
