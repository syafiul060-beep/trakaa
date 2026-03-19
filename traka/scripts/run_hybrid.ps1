# Run Flutter Traka dengan mode hybrid (development)
# Usage: .\scripts\run_hybrid.ps1
#        .\scripts\run_hybrid.ps1 -ApiUrl "https://trakaa-production.up.railway.app"

param(
    [Parameter(Mandatory=$false)]
    [string]$ApiUrl = "https://trakaa-production.up.railway.app",
    [Parameter(Mandatory=$false)]
    [string]$Device = ""
)

# Pastikan jalan dari root proyek (traka/) supaya android/key.properties terbaca
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Set-Location $projectRoot

$url = $ApiUrl.TrimEnd('/')
Write-Host "Running Traka Hybrid - API: $url" -ForegroundColor Cyan

# Baca MAPS_API_KEY dari key.properties (untuk Directions API & peta)
$mapsKey = ""
$keyPath = Join-Path $projectRoot "android\key.properties"
if (Test-Path $keyPath) {
    $content = Get-Content $keyPath -Raw
    if ($content -match "MAPS_API_KEY=(\S+)") { $mapsKey = $matches[1].Trim() }
}

$args = @("run")
if ($Device) { $args += "-d", $Device }
$args += "--dart-define=TRAKA_API_BASE_URL=$url", "--dart-define=TRAKA_USE_HYBRID=true"
if ($mapsKey) {
    Write-Host "MAPS_API_KEY: $($mapsKey.Substring(0,10))..." -ForegroundColor Green
    $args += "--dart-define=MAPS_API_KEY=$mapsKey"
} else {
    Write-Host "WARNING: MAPS_API_KEY tidak ditemukan di android/key.properties. Rute/peta akan GAGAL." -ForegroundColor Yellow
    Write-Host "Pastikan android/key.properties berisi baris: MAPS_API_KEY=AIzaSy..." -ForegroundColor Yellow
}
& flutter $args
