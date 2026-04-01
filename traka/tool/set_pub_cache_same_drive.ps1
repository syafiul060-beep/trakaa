# Set PUB_CACHE ke folder di drive yang sama dengan project (hindari error Gradle
# "this and base files have different roots" saat project di D: dan cache bawaan di C:).
#
# Jalankan SEKALI di PowerShell (boleh tanpa admin):
#   cd D:\Traka\traka\tool
#   .\set_pub_cache_same_drive.ps1
# Lalu tutup semua terminal & IDE, buka lagi, jalankan:
#   cd D:\Traka\traka
#   flutter pub get
#   flutter clean
#   cd android; .\gradlew --stop; cd ..
#
$projectRoot = Split-Path -Parent $PSScriptRoot
$cacheDir = Join-Path $projectRoot ".pub-cache"
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
[Environment]::SetEnvironmentVariable("PUB_CACHE", $cacheDir, "User")
Write-Host "PUB_CACHE diset permanen (User) ke:"
Write-Host "  $cacheDir"
Write-Host ""
Write-Host "Restart Cursor/VS Code/Android Studio, lalu flutter pub get."
