# Build Flutter Traka dengan mode hybrid (Phase 1)
# Usage: .\scripts\build_hybrid.ps1 -ApiUrl "https://trakaa-production.up.railway.app"
#        .\scripts\build_hybrid.ps1 -ApiUrl "https://trakaa-production.up.railway.app" -Target appbundle

param(
    [Parameter(Mandatory=$false)]
    [string]$ApiUrl = "https://trakaa-production.up.railway.app",
    [ValidateSet("apk","appbundle","ios")]
    [string]$Target = "apk"
)

# Pastikan jalan dari root proyek (sama seperti run_hybrid.ps1)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Set-Location $projectRoot

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

switch ($Target) {
    "apk"       { flutter build apk $dartDefines }
    "appbundle" { flutter build appbundle $dartDefines }
    "ios"       { flutter build ios $dartDefines }
}
