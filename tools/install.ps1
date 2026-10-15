<#
.SYNOPSIS
  Instala o APK do JTMobile no celular Android conectado por USB (ou ADB sem fio).

.DESCRIPTION
  Localiza o adb (PATH ou Android SDK padrão), lista os aparelhos, verifica se há exatamente um
  dispositivo autorizado e instala/atualiza o APK (-r preserva os dados do app).

.PARAMETER Apk
  Caminho do APK. Padrão: dist\JTMobile-arm64-v8a.apk (arm64 = celulares atuais).

.PARAMETER Serial
  Número de série do aparelho (opcional, quando há mais de um conectado). Veja "adb devices".

.PARAMETER Launch
  Abre o app depois de instalar.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\tools\install.ps1 -Apk "C:\JTDX_Mobile\dist\JTMobile-arm64-v8a.apk" -Launch
#>
param(
    [string]$Apk = (Join-Path $PSScriptRoot "..\dist\JTMobile-arm64-v8a.apk"),
    [string]$Serial = "",
    [switch]$Launch
)

$ErrorActionPreference = "Stop"

# 1) localizar o adb
$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) {
    $candidate = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
    if (Test-Path $candidate) { $adb = $candidate }
}
if (-not $adb) { throw "adb nao encontrado. Instale o Android SDK Platform-Tools ou adicione o adb ao PATH." }

# 2) validar o APK
$Apk = (Resolve-Path $Apk).Path
if (-not (Test-Path $Apk)) { throw "APK nao encontrado: $Apk" }
Write-Host "APK: $Apk ($([math]::Round((Get-Item $Apk).Length/1MB,1)) MB)"

# 3) escolher o dispositivo
& $adb start-server | Out-Null
$lines = (& $adb devices) | Select-Object -Skip 1 | Where-Object { $_ -match "\S" }
$ready = @($lines | Where-Object { $_ -match "\sdevice$" } | ForEach-Object { ($_ -split "\s+")[0] })
$unauth = @($lines | Where-Object { $_ -match "unauthorized" })
if ($unauth.Count -gt 0 -and $ready.Count -eq 0) {
    throw "Aparelho nao autorizado: aceite 'Permitir depuracao USB' na tela do celular e rode de novo."
}
if ($ready.Count -eq 0) {
    throw "Nenhum aparelho conectado. Ligue a Depuracao USB, conecte o cabo e confirme com 'adb devices'."
}
if ($Serial -eq "") {
    if ($ready.Count -gt 1) { throw "Mais de um aparelho: use -Serial. Disponiveis: $($ready -join ', ')" }
    $Serial = $ready[0]
}
Write-Host "Dispositivo: $Serial"

# 4) instalar
& $adb -s $Serial install -r $Apk
if ($LASTEXITCODE -ne 0) { throw "Falha na instalacao (codigo $LASTEXITCODE)." }
Write-Host "Instalado com sucesso."

# 5) abrir o app (opcional)
if ($Launch) {
    & $adb -s $Serial shell am start -n br.poinsp.ft_mobile/.MainActivity | Out-Null
    Write-Host "App iniciado."
}
