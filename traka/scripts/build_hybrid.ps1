# Build Flutter Traka dengan mode hybrid (Phase 1)
# Usage: .\scripts\build_hybrid.ps1 -ApiUrl "https://trakaa-production.up.railway.app"
#        .\scripts\build_hybrid.ps1 -ApiUrl "https://trakaa-production.up.railway.app" -Target appbundle
#        .\scripts\build_hybrid.ps1 -EnableMapWs -RealtimeWsUrl "https://<worker>.up.railway.app"
#        .\scripts\build_hybrid.ps1 -CertSha256 "AA:BB:..."  # opsional: TRAKA_API_CERT_SHA256
#        .\scripts\build_hybrid.ps1 -CreateOrderViaApi      # POST /api/orders + fallback Firestore
#        .\scripts\build_hybrid.ps1 -Debug                   # APK debug (kompilasi lebih cepat, uji USB)

param(
    [Parameter(Mandatory=$false)]
    [string]$ApiUrl = "https://trakaa-production.up.railway.app",
    [Parameter(Mandatory=$false)]
    [string]$CertSha256 = "",
    [Parameter(Mandatory=$false)]
    [string]$RealtimeWsUrl = "",
    [Parameter(Mandatory=$false)]
    [switch]$EnableMapWs,
    [ValidateSet("apk","appbundle","ios")]
    [string]$Target = "apk",
    [Parameter(Mandatory=$false)]
    [switch]$CreateOrderViaApi,
    [Parameter(Mandatory=$false)]
    [switch]$Debug
)

# Pastikan jalan dari root proyek (sama seperti run_hybrid.ps1)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Set-Location $projectRoot
& (Join-Path $scriptDir "ensure_pub_cache_same_drive.ps1") -ProjectRoot $projectRoot

$url = $ApiUrl.TrimEnd('/')
Write-Host "Building Traka Hybrid - API: $url" -ForegroundColor Cyan

# Baca MAPS_API_KEY dari key.properties (untuk Directions API)
$mapsKey = ""
$keyPath = Join-Path $projectRoot "android\key.properties"
if (Test-Path $keyPath) {
    $content = Get-Content $keyPath -Raw
    if ($content -match "MAPS_API_KEY=(\S+)") { $mapsKey = $matches[1].Trim() }
}
if ($mapsKey) {
    Write-Host "MAPS_API_KEY: $($mapsKey.Substring(0,10))..." -ForegroundColor Green
    $dartDefines = "--dart-define=TRAKA_API_BASE_URL=$url --dart-define=TRAKA_USE_HYBRID=true --dart-define=MAPS_API_KEY=$mapsKey"
} else {
    Write-Host "WARNING: MAPS_API_KEY tidak ditemukan. Rute akan GAGAL." -ForegroundColor Yellow
    $dartDefines = "--dart-define=TRAKA_API_BASE_URL=$url --dart-define=TRAKA_USE_HYBRID=true"
}
if ($CreateOrderViaApi) {
    $dartDefines = "$dartDefines --dart-define=TRAKA_CREATE_ORDER_VIA_API=true"
    Write-Host "Create order: TRAKA_CREATE_ORDER_VIA_API=true (POST /api/orders)" -ForegroundColor Cyan
}

$cert = $CertSha256.Trim()
if ($cert) {
    $dartDefines = "$dartDefines --dart-define=TRAKA_API_CERT_SHA256=$cert"
    Write-Host "Certificate pinning: SHA256 disetel (TRAKA_API_CERT_SHA256)" -ForegroundColor Cyan
}

$rt = $RealtimeWsUrl.Trim()
if ($EnableMapWs -and $rt) {
    $dartDefines = "$dartDefines --dart-define=TRAKA_ENABLE_MAP_WS=true --dart-define=TRAKA_REALTIME_WS_URL=$rt"
    Write-Host "Realtime map WS: $rt" -ForegroundColor Cyan
}

switch ($Target) {
    "apk" {
        if ($Debug) {
            Write-Host "APK mode: DEBUG (uji USB / iterasi cepat)" -ForegroundColor Cyan
            flutter build apk --debug $dartDefines
        } else {
            flutter build apk $dartDefines
        }
    }
    "appbundle" {
        if ($Debug) { Write-Host "WARNING: -Debug diabaikan untuk appbundle." -ForegroundColor Yellow }
        flutter build appbundle $dartDefines
    }
    "ios" {
        if ($Debug) { Write-Host "WARNING: -Debug untuk iOS — gunakan scheme/profile Xcode jika perlu." -ForegroundColor Yellow }
        flutter build ios $dartDefines
    }
}