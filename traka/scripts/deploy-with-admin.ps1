# Deploy Traka dengan Web Admin ke syafiul-traka.web.app
# Menjalankan: cd d:\Traka\traka; .\scripts\deploy-with-admin.ps1

$trakaRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$trakaAdmin = Join-Path $trakaRoot "traka-admin"
$trakaDir = Join-Path $trakaRoot "traka"

Write-Host "Building traka-admin..." -ForegroundColor Cyan
Set-Location $trakaAdmin
npm run build
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "Copying admin to hosting/admin..." -ForegroundColor Cyan
Set-Location $trakaDir
$adminDest = Join-Path $trakaDir "hosting\admin"
if (Test-Path $adminDest) { Remove-Item -Recurse -Force $adminDest }
Copy-Item -Recurse (Join-Path $trakaAdmin "dist") $adminDest

Write-Host "Deploying to Firebase (syafiul-traka.web.app)..." -ForegroundColor Cyan
firebase deploy --only hosting
Write-Host "Done! Admin: https://syafiul-traka.web.app/admin" -ForegroundColor Green
