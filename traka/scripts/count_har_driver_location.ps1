#Requires -Version 7.0
<#
.SYNOPSIS
  Hitung request dari file HAR (HTTP Archive) untuk audit POST lokasi driver hybrid.

.DESCRIPTION
  Berguna setelah export HAR dari mitmproxy, Charles, Fiddler, atau Android Studio
  Network Inspector — lihat docs/AUDIT_DRIVER_STATUS_DAN_HYBRID.md §3.2–3.3.

.EXAMPLE
  pwsh .\scripts\count_har_driver_location.ps1 -Path C:\temp\traka-session.har

.EXAMPLE
  pwsh .\scripts\count_har_driver_location.ps1 -Path .\session.har -VerboseEndpoints
#>
param(
    [Parameter(Mandatory = $true)]
    [string] $Path,

    [string] $LocationSubpath = '/api/driver/location',

    [switch] $VerboseEndpoints,

    [switch] $IncludePatchStatus,

    [switch] $IncludeDeleteStatus
)

$full = Resolve-Path -LiteralPath $Path -ErrorAction Stop
$raw = Get-Content -LiteralPath $full -Raw -Encoding UTF8
$har = $raw | ConvertFrom-Json -Depth 100

if (-not $har.log -or -not $har.log.entries) {
    Write-Error "HAR tidak punya log.entries — pastikan format HAR 1.2."
    exit 1
}

$entries = @($har.log.entries)
$locLower = $LocationSubpath.ToLowerInvariant()
$statusPath = '/api/driver/status'

function Match-Url([string] $url, [string] $needle) {
    if ([string]::IsNullOrEmpty($url)) { return $false }
    return $url.ToLowerInvariant().Contains($needle.ToLowerInvariant())
}

$posts = [System.Collections.Generic.List[object]]::new()
$patchCount = 0
$deleteCount = 0

foreach ($e in $entries) {
    $req = $e.request
    if (-not $req) { continue }
    $method = [string] $req.method
    $url = [string] $req.url

    if ($method -eq 'POST' -and (Match-Url $url $locLower)) {
        $posts.Add([pscustomobject]@{
                Started = [datetime]::Parse($e.startedDateTime, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                Url     = $url
            })
    }
    if ($IncludePatchStatus -and $method -eq 'PATCH' -and (Match-Url $url $statusPath)) {
        $patchCount++
    }
    if ($IncludeDeleteStatus -and $method -eq 'DELETE' -and (Match-Url $url $statusPath)) {
        $deleteCount++
    }
}

$n = $posts.Count
Write-Host "HAR: $full"
Write-Host "POST *$LocationSubpath* : $n"

if ($n -eq 0) {
    Write-Host "(Tidak ada POST yang cocok — cek URL API atau filter export.)"
    exit 0
}

# UTC minute buckets
$byMinute = $posts | Group-Object { $_.Started.ToUniversalTime().ToString('yyyy-MM-dd HH:mm') } | Sort-Object Name
Write-Host ""
Write-Host "Per menit (UTC):"
foreach ($g in $byMinute) {
    Write-Host ("  {0,-16} {1,4}" -f $g.Name, $g.Count)
}

$first = ($posts | Sort-Object Started | Select-Object -First 1).Started
$last = ($posts | Sort-Object Started | Select-Object -Last 1).Started
$spanMin = [math]::Max(1, [math]::Ceiling(($last - $first).TotalMinutes))
$avg = [math]::Round($n / $spanMin, 2)
Write-Host ""
Write-Host "Jendela: $first .. $last (~$spanMin menit) => rata-rata ~$avg POST/menit (kasar)"

# Sliding 10s max
$sorted = $posts | Sort-Object Started | ForEach-Object { $_.Started }
$maxBurst = 0
for ($i = 0; $i -lt $sorted.Count; $i++) {
    $t0 = $sorted[$i]
    $c = 0
    for ($j = $i; $j -lt $sorted.Count; $j++) {
        if (($sorted[$j] - $t0).TotalSeconds -le 10) { $c++ } else { break }
    }
    if ($c -gt $maxBurst) { $maxBurst = $c }
}
Write-Host "Puncak burst (sliding 10 dtk): $maxBurst request"

if ($IncludePatchStatus) { Write-Host "PATCH *$statusPath* : $patchCount" }
if ($IncludeDeleteStatus) { Write-Host "DELETE *$statusPath* : $deleteCount" }

if ($VerboseEndpoints) {
    Write-Host ""
    Write-Host "URLs (potong query):"
    $posts | ForEach-Object {
        $u = $_.Url -replace '\?.*$', ''
        Write-Host ("  {0:o}  {1}" -f $_.Started, $u)
    }
}
