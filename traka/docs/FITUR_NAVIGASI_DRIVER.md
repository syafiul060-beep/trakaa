# Fitur Navigasi Driver

Dokumentasi fitur navigasi dan chase cam untuk layar driver Traka.

**Rencana lengkap:** `docs/RENCANA_NAVIGASI_DRIVER.md`

## Chase Cam (GTA-style)

Kamera mengikuti mobil dengan gaya game: mobil di bawah layar, jalan ke depan di atas.

### Parameter (driver_screen.dart)

| Parameter | Nilai | Keterangan |
|-----------|-------|------------|
| `_trackingZoom` | 19.0 | Detail jalan terlihat |
| `_trackingTilt` | 58° | Sudut pandang 3D |
| `_getCameraOffsetAheadMeters()` | 120–320 m | Offset dinamis ala Grab: mobil selalu terlihat |
| `maxDistanceMeters` | 400 m | Batas pointAheadOnPolyline |

### Konsistensi Penumpang

Layar **Lacak Driver** (`passenger_track_map_widget.dart`) memakai parameter sinkron: zoom 18, tilt 58°, offset 220 m (fixed), bearing hysteresis 6°, alpha 0.06, `pointAheadOnPolyline` untuk target kamera.

## Voice Guidance

- **Paket:** `flutter_tts`
- **Service:** `lib/services/voice_navigation_service.dart`
- **Bahasa:** Indonesia (id-ID)
- **Mute:** Icon speaker di overlay "Menuju penumpang", state disimpan di SharedPreferences

### Trigger suara

1. Saat step turn-by-turn berubah (belok kiri/kanan/lurus/putar balik)
2. Saat jarak ke penumpang < 100 m: "Hampir sampai di lokasi penumpang"

## Haptic Feedback

- Getar saat **step berubah** (mendekati belokan)
- Getar saat **jarak < 100 m** ke penumpang

## Portrait Lock

- **File:** `lib/main.dart`
- `SystemChrome.setPreferredOrientations([portraitUp, portraitDown])`
- HP landscape tetap tampil portrait

## Fallback Tile (Offline Map)

- **File:** `lib/services/tile_layer_service.dart`
- Jika OSM 403, otomatis fallback ke Carto: `cartodb-basemaps-a.global.ssl.fastly.net`
- Tidak perlu API key

## Animasi Kamera

- Durasi proporsional dengan jarak perpindahan: 250–1100 ms
- Jarak kecil → animasi cepat; jarak besar → lebih halus
- **Saat berhenti:** target kamera < 5 m → skip animasi (peta stabil)

## Update GPS

- **Saat bekerja:** setiap **2 detik** (hemat baterai, tetap halus)
- **Saat tidak bekerja:** setiap 30 detik

## Skenario Navigasi

| Skenario | Perilaku |
|----------|----------|
| **Rute dipilih, belum mulai** | Titik biru besar (marker di peta) |
| **Berjalan** | Segitiga biru dalam oval putih, kamera ikuti 120–320 m di depan (offset dinamis) |
| **Berhenti** | Titik biru besar, kamera stabil (skip animasi) |
| **Jemput penumpang** | Live tracking 50 m / 5 detik ke Firestore, turn-by-turn, rute ke penumpang |

## Perilaku Peta

- **Icon tetap** di bawah tengah layar
- **Jalan lurus:** peta bergerak menurun (target kamera bergeser ke depan)
- **Belok kiri/kanan:** peta berputar sesuai arah rute (bearing dari polyline)

## Snap ke Rute

- Posisi tampilan di-proyeksikan ke polyline (projectPointOntoPolyline, max 150 m)
- Titik/panah tersinkron dengan garis biru sampai tujuan

## Warna Rute Dinamis

- Sudah dilewati: kuning (amber)
- Belum dilewati: biru / hijau (rute ke penumpang)

## Re-routing

- Keluar rute: garis biru ke jalan lain untuk kembali ke tujuan

## Icon Lokasi Driver (Beranda saja)

- **Titik biru** (#4285F4): saat diam (rute dipilih belum mulai, atau berhenti)
- **Segitiga biru dalam oval putih**: saat bergerak (arah mengikuti bearing)
- File: `lib/widgets/driver_location_overlay.dart`, `lib/services/driver_location_icon_service.dart`
