# Build Flutter Traka dengan mode hybrid (Phase 1)
# Usage: .\scripts\build_hybrid.ps1 -ApiUrl "https://traka-api.example.com"
#        .\scripts\build_hybrid.ps1 -ApiUrl "https://traka-api.example.com" -Target apk

param(
    [Parameter(Mandatory=$true)]
    [string]$ApiUrl,
    [ValidateSet("apk","appbundle","ios")]
    [string]$Target = "apk"
)

$url = $ApiUrl.TrimEnd('/')
Write-Host "Building Traka Hybrid - API: $url" -ForegroundColor Cyan

$dartDefines = "--dart-define=TRAKA_API_BASE_URL=$url --dart-define=TRAKA_USE_HYBRID=true"

switch ($Target) {
    "apk"       { flutter build apk $dartDefines }
    "appbundle" { flutter build appbundle $dartDefines }
    "ios"       { flutter build ios $dartDefines }
}
