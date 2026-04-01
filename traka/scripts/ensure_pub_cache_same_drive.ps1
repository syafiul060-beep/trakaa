# Hindari error Gradle/Kotlin di Windows: "this and base files have different roots"
# saat repo di drive lain dari PUB_CACHE (mis. proyek D:\, cache C:\Users\...\Pub\Cache).
# Panggil dari run_hybrid / build_hybrid sebelum flutter.
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
)

function Get-DriveLetter([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    if ($path -match '^([A-Za-z]):') { return $matches[1].ToUpperInvariant() }
    return $null
}

$resolved = try {
    (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).Path
}
catch {
    $ProjectRoot
}

$projDrive = Get-DriveLetter $resolved
$effectiveCache = $env:PUB_CACHE
if (-not $effectiveCache) {
    if ($env:LOCALAPPDATA) {
        $effectiveCache = Join-Path $env:LOCALAPPDATA "Pub\Cache"
    }
}
$cacheDrive = Get-DriveLetter $effectiveCache

if ($projDrive -and $cacheDrive -and $projDrive -ne $cacheDrive) {
    $localPubCache = Join-Path $resolved ".pub-cache"
    New-Item -ItemType Directory -Force -Path $localPubCache | Out-Null
    $env:PUB_CACHE = $localPubCache
    Write-Host "[PUB_CACHE] $localPubCache  (drive $projDrive = proyek; hindari error lintas drive untuk plugin Android)" -ForegroundColor DarkCyan
}
