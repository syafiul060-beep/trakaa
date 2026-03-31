# Build APK hybrid + pasang ke HP lewat USB (adb). Tanpa Play Store.
# Prasyarat: HP mode pengembang + USB debugging, adb di PATH (Android SDK platform-tools).
#
# Contoh:
#   .\scripts\install_hybrid_usb.ps1 -ApiUrl "https://trakaa-production.up.railway.app"
#   .\scripts\install_hybrid_usb.ps1 -Debug   # APK debug — build lebih cepat untuk coba
#   .\scripts\install_hybrid_usb.ps1 -Serial "ABC123XYZ"   # jika ada lebih dari satu perangkat

param(
    [Parameter(Mandatory=$false)]
    [string]$ApiUrl = "https://trakaa-production.up.railway.app",
    [Parameter(Mandatory=$false)]
    [string]$CertSha256 = "",
    [Parameter(Mandatory=$false)]
    [string]$RealtimeWsUrl = "",
    [Parameter(Mandatory=$false)]
    [switch]$EnableMapWs,
    [Parameter(Mandatory=$false)]
    [switch]$CreateOrderViaApi,
    [Parameter(Mandatory=$false)]
    [switch]$Debug,
    [Parameter(Mandatory=$false)]
    [string]$Serial = ""
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Set-Location $projectRoot

$adb = Get-Command adb -ErrorAction SilentlyContinue
if (-not $adb) {
    Write-Host "ERROR: adb tidak ada di PATH. Tambahkan folder platform-tools (Android SDK), lalu buka terminal baru." -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Perangkat USB (adb devices) ===" -ForegroundColor Cyan
adb devices -l
$deviceLines = adb devices | Where-Object { $_ -match "`tdevice$" }
$n = @($deviceLines).Count
if ($n -eq 0) {
    Write-Host "ERROR: Tidak ada perangkat 'device'. Colok USB, izinkan debugging, coba lagi." -ForegroundColor Red
    exit 1
}
if ($n -gt 1 -and -not $Serial) {
    Write-Host "ERROR: Lebih dari satu HP. Pilih serial dari daftar di atas, lalu:" -ForegroundColor Red
    Write-Host '  .\scripts\install_hybrid_usb.ps1 -Serial "SERIAL_DARI_KOLOM_PERTAMA" ...' -ForegroundColor Yellow
    exit 1
}

$buildScript = Join-Path $scriptDir "build_hybrid.ps1"
$buildArgs = @{
    ApiUrl = $ApiUrl
    Target = "apk"
}
if ($Debug) { $buildArgs["Debug"] = $true }
if ($CertSha256) { $buildArgs["CertSha256"] = $CertSha256 }
if ($RealtimeWsUrl) { $buildArgs["RealtimeWsUrl"] = $RealtimeWsUrl }
if ($EnableMapWs) { $buildArgs["EnableMapWs"] = $true }
if ($CreateOrderViaApi) { $buildArgs["CreateOrderViaApi"] = $true }

Write-Host "`n=== Membangun APK hybrid ===" -ForegroundColor Cyan
& $buildScript @buildArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build gagal (exit $LASTEXITCODE)." -ForegroundColor Red
    exit $LASTEXITCODE
}

$apkName = if ($Debug) { "app-debug.apk" } else { "app-release.apk" }
$apk = Join-Path $projectRoot "build\app\outputs\flutter-apk\$apkName"
if (-not (Test-Path $apk)) {
    Write-Host "ERROR: APK tidak ditemukan: $apk" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Memasang ke HP: $apkName ===" -ForegroundColor Cyan
if ($Serial) {
    adb -s $Serial install -r $apk
} else {
    adb install -r $apk
}
if ($LASTEXITCODE -ne 0) {
    Write-Host "adb install gagal. Coba cabut USB, aktifkan lagi file transfer, atau pakai -Serial." -ForegroundColor Red
    exit $LASTEXITCODE
}
Write-Host "`nSelesai. Buka launcher Traka di HP (bukan update dari Play Store)." -ForegroundColor Green
Write-Host "Iterasi paling cepat tanpa install ulang tiap kali: .\scripts\run_hybrid.bat -Profile -ApiUrl `"$ApiUrl`" -Device <id dari flutter devices>" -ForegroundColor DarkGray
