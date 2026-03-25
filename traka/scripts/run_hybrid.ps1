# Run Flutter Traka dengan mode hybrid (development)
# Usage: .\scripts\run_hybrid.ps1
#        .\scripts\run_hybrid.ps1 -ApiUrl "https://trakaa-production.up.railway.app"
#        .\scripts\run_hybrid.ps1 -EnableMapWs -RealtimeWsUrl "https://<worker>.up.railway.app"
#        .\scripts\run_hybrid.ps1 -Profile -EnableMapWs -RealtimeWsUrl "https://..."   # DevTools / performa
#        .\scripts\run_hybrid.ps1 -CertSha256 "AA:BB:..."
#        .\scripts\run_hybrid.ps1 -CreateOrderViaApi   # POST /api/orders + fallback Firestore

param(
    [Parameter(Mandatory=$false)]
    [string]$ApiUrl = "https://trakaa-production.up.railway.app",
    [Parameter(Mandatory=$false)]
    [string]$CertSha256 = "",
    [Parameter(Mandatory=$false)]
    [string]$Device = "",
    [Parameter(Mandatory=$false)]
    [string]$RealtimeWsUrl = "",
    [Parameter(Mandatory=$false)]
    [switch]$EnableMapWs,
    [Parameter(Mandatory=$false)]
    [switch]$CreateOrderViaApi,
    [Parameter(Mandatory=$false)]
    [switch]$Profile
)

# Pastikan jalan dari root proyek (traka/) supaya android/key.properties terbaca
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Set-Location $projectRoot

$url = $ApiUrl.TrimEnd('/')
$mode = if ($Profile) { "PROFILE (DevTools / ukur frame)" } else { "debug" }
Write-Host "Running Traka Hybrid ($mode) - API: $url" -ForegroundColor Cyan

# Baca MAPS_API_KEY dari key.properties (untuk Directions API & peta)
$mapsKey = ""
$keyPath = Join-Path $projectRoot "android\key.properties"
if (Test-Path $keyPath) {
    $content = Get-Content $keyPath -Raw
    if ($content -match "MAPS_API_KEY=(\S+)") { $mapsKey = $matches[1].Trim() }
}

$args = @("run")
if ($Profile) { $args += "--profile" }
if ($Device) { $args += "-d", $Device }
$args += "--dart-define=TRAKA_API_BASE_URL=$url", "--dart-define=TRAKA_USE_HYBRID=true"
if ($CreateOrderViaApi) {
    $args += "--dart-define=TRAKA_CREATE_ORDER_VIA_API=true"
    Write-Host "Create order: TRAKA_CREATE_ORDER_VIA_API=true (POST /api/orders)" -ForegroundColor Cyan
}
$cert = $CertSha256.Trim()
if ($cert) {
    $args += "--dart-define=TRAKA_API_CERT_SHA256=$cert"
    Write-Host "Certificate pinning: TRAKA_API_CERT_SHA256 disetel" -ForegroundColor Cyan
}
if ($mapsKey) {
    Write-Host "MAPS_API_KEY: $($mapsKey.Substring(0,10))..." -ForegroundColor Green
    $args += "--dart-define=MAPS_API_KEY=$mapsKey"
} else {
    Write-Host "WARNING: MAPS_API_KEY tidak ditemukan di android/key.properties. Rute/peta akan GAGAL." -ForegroundColor Yellow
    Write-Host "Pastikan android/key.properties berisi baris: MAPS_API_KEY=AIzaSy..." -ForegroundColor Yellow
}

$rt = $RealtimeWsUrl.Trim()
if ($EnableMapWs -and $rt) {
    $args += "--dart-define=TRAKA_ENABLE_MAP_WS=true", "--dart-define=TRAKA_REALTIME_WS_URL=$rt"
    Write-Host "Realtime map WS (Tahap 4): $rt" -ForegroundColor Cyan
} elseif ($EnableMapWs -and -not $rt) {
    Write-Host "WARNING: -EnableMapWs tanpa -RealtimeWsUrl - WS tidak diaktifkan." -ForegroundColor Yellow
}
& flutter $args
