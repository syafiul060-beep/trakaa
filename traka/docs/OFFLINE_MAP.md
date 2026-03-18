# Peta Offline (Cache)

## Overview

Traka memakai **flutter_map** + **flutter_map_cache** untuk caching tile peta. Tile yang pernah dilihat akan tersimpan dan tersedia saat sinyal lemah.

## Manfaat

- **Driver tetap bisa lihat peta** walau sinyal jelek (penting untuk daerah luar kota)
- **Performa ringan** – FlutterMap pure Flutter, lebih smooth di HP spek rendah
- **Animasi halus** – banyak dev melaporkan lebih halus dari Google Maps SDK
- **Tanpa API key** untuk tile – pakai OpenStreetMap (gratis)

## Cara Kerja

1. **Browse caching** – Tile di-cache otomatis saat user melihat area di peta
2. **Cache 30 hari** – Tile tersimpan hingga 30 hari
3. **Offline Map Screen** – Driver bisa buka "Cache peta offline" di Profil → zoom/pan ke rute → tile ter-cache

## Akses

- **Driver:** Profil (tab Saya) → Cache peta offline
- Buka layar, zoom/pan ke area yang akan dilalui, lalu tutup. Saat sinyal lemah, peta area tersebut tetap tampil.

## Teknis

- **Package:** `flutter_map`, `flutter_map_cache`, `http_cache_file_store`
- **Tile:** OpenStreetMap (`tile.openstreetmap.org`)
- **Storage:** `getTemporaryDirectory()/TrakaMapTiles`
- **Init:** `TileLayerService.ensureInitialized()` di `main.dart`

## Night Mode

Layar offline map memakai **MapStyleService.themeNotifier** dan **isNightTimeNotifier** (sama dengan peta utama). Peta gelap otomatis jam 18:00–06:00. Lihat `docs/REFACTOR_7_TAHAP.md` Tahap 3.

## Catatan

- Peta utama (driver_screen, penumpang_screen, Lacak Driver) masih pakai **Google Maps** untuk saat ini
- Layar "Cache peta offline" memakai **FlutterMap** untuk pre-cache tile
- Untuk migrasi penuh ke FlutterMap di semua layar, lihat rencana di `docs/`

## Download Area Tertentu

Untuk fitur "download area tertentu" (seperti Google Maps offline), gunakan **flutter_map_tile_caching** (FMTC). FMTC mendukung:
- Download region (circle, polygon)

**Catatan:** FMTC berlisensi GPL-v3. Untuk app komersial, cek [proprietary licensing](https://fmtc.jaffaketchup.dev/proprietary-licensing).
