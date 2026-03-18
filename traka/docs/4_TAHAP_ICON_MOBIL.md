# 4 Tahap Perbaikan Icon Mobil

Ringkasan tahap perbaikan icon mobil di peta (Driver, Lacak Driver, Cari driver).

---

## Status

| Tahap | Deskripsi | Status |
|-------|-----------|--------|
| **1** | Bearing smoothing (EMA + hysteresis 5°) | ✅ Selesai |
| **2** | Asset PNG resolusi retina (2x–3x) | ✅ Selesai |
| **3** | Durasi animasi kamera proporsional (jarak/kecepatan) | ✅ Selesai |
| **4** | Panduan custom icon ala Grab/Uber/InDrive | ✅ Selesai |

---

## Detail

### Tahap 1: Bearing smoothing
- **File:** `driver_screen.dart`, `passenger_track_map_widget.dart`
- **Implementasi:** EMA (alpha 0.2) + hysteresis 5° untuk mengurangi getar rotasi ikon saat driver bergerak
- **Rotasi:** `rotation = (bearing + 180) % 360`
- **Lihat:** `ASSET_ICON_MOBIL.md` → Orientasi

### Tahap 2: Asset PNG resolusi retina
- **File:** `assets/images/car_merah.png`, `car_hijau.png`
- **Implementasi:** Decode 2x–3x untuk layar retina (targetWidth ~100–280 px)
- **Fallback:** `BitmapDescriptor.defaultMarkerWithHue` (merah/hijau) saat asset belum load
- **Lihat:** `ASSET_ICON_MOBIL.md` → Resolusi

### Tahap 3: Durasi animasi proporsional
- **File:** `driver_screen.dart`, `passenger_track_map_widget.dart`
- **Implementasi:** `duration = 200 + (jarak_meter / 200) × 600 ms` (clamp 200–800 ms)
- **Variabel:** `_lastCameraTarget` untuk hitung jarak perpindahan target kamera
- **Efek:** Jarak kecil → animasi cepat; jarak besar → animasi lebih lama agar halus

### Tahap 4: Panduan custom icon
- **Lihat:** `TAHAP_4_CUSTOM_ICON_MOBIL.md`
- **Isi:** Spesifikasi desain, sumber icon gratis, langkah penggantian, troubleshooting
- **Asset:** Ganti `car_merah.png` dan `car_hijau.png` di `assets/images/`

---

## File Terkait

| File | Peran |
|------|--------|
| `lib/services/car_icon_service.dart` | Load icon terpusat (CarIconService) |
| `lib/screens/driver_screen.dart` | Kamera tracking, bearing smoothing, pakai CarIconService |
| `lib/widgets/passenger_track_map_widget.dart` | Lacak driver, bearing smoothing, pakai CarIconService |
| `lib/screens/penumpang_screen.dart` | Cari driver aktif, pakai CarIconService |
| `lib/screens/cari_travel_screen.dart` | Cari Travel, pakai CarIconService (car_merah/car_hijau) |
| `lib/screens/data_order_driver_screen.dart` | Map driver/penumpang, pakai CarIconService |
| `assets/images/car_merah.png` | Driver diam |
| `assets/images/car_hijau.png` | Driver bergerak |

**Lihat:** `docs/REFACTOR_7_TAHAP.md` Tahap 2 untuk detail migrasi CarIconService.
