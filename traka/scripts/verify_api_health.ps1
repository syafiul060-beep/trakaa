# Verifikasi GET /health untuk gate Tahap 3 (Redis + API).
# Usage:
#   .\scripts\verify_api_health.ps1
#   .\scripts\verify_api_health.ps1 -ApiUrl "https://api.example.com"
# Exit 0 = ok + redis true; exit 1 = gagal.
# Catatan: hindari " - " sebelum $var di string ganda (PowerShell mengartikan sebagai operator).

param(
    [Parameter(Mandatory = $false)]
    [string]$ApiUrl = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$trakaRoot = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent $trakaRoot

if (-not $ApiUrl) {
    $txtPath = Join-Path $repoRoot "PRODUCTION_API_BASE_URL.txt"
    if (-not (Test-Path $txtPath)) {
        Write-Host ('FAIL: PRODUCTION_API_BASE_URL.txt tidak ada di {0}; set -ApiUrl manual.' -f $repoRoot) -ForegroundColor Red
        exit 1
    }
    foreach ($line in Get-Content $txtPath) {
        $t = $line.Trim()
        if ($t.StartsWith("https://")) {
            $ApiUrl = $t
            break
        }
    }
}

$ApiUrl = $ApiUrl.TrimEnd('/')
if (-not $ApiUrl) {
    Write-Host "FAIL: URL API kosong." -ForegroundColor Red
    exit 1
}

$uri = "$ApiUrl/health"
Write-Host "GET $uri" -ForegroundColor Cyan

try {
    $raw = curl.exe -sS -m 25 -f "$uri"
} catch {
    Write-Host ('FAIL: request error: {0}' -f $_) -ForegroundColor Red
    exit 1
}

if (-not $raw) {
    Write-Host "FAIL: body kosong" -ForegroundColor Red
    exit 1
}

try {
    $j = $raw | ConvertFrom-Json
} catch {
    Write-Host ('FAIL: bukan JSON valid: {0}' -f $raw) -ForegroundColor Red
    exit 1
}

if (-not $j.ok) {
    Write-Host ('FAIL: ok=false; body={0}' -f $raw) -ForegroundColor Red
    exit 1
}

$redis = $j.checks.redis
if ($null -eq $redis -or -not [bool]$redis) {
    Write-Host ('FAIL: checks.redis bukan true (Tahap 3 butuh Redis). Body: {0}' -f $raw) -ForegroundColor Red
    exit 1
}

Write-Host ('OK: ok=true, checks.redis=true (pg={0}, api={1})' -f $j.checks.pg, $j.checks.api) -ForegroundColor Green
if ($j.version) {
    Write-Host ('    version={0}' -f $j.version) -ForegroundColor Gray
}
exit 0
