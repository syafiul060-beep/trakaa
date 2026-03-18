# Analisis Tumpang Tindih (Overlap) di Aplikasi Traka

Dokumen ini mendokumentasikan kode yang tumpang tindih atau duplikat untuk referensi refactor.

---

## 4 Tahap Perbaikan Tumpang Tindih

| Tahap | Deskripsi | Status |
|-------|-----------|--------|
| **1** | CarIconLoader service (ekstrak load icon mobil) | ✅ Selesai → CarIconService |
| **2** | GeocodingService (centralize geocode) | ✅ Selesai |
| **3** | DestinationAutocompleteService (autocomplete tujuan) | ✅ Selesai |
| **4** | Cleanup minor (_formatPlacemarkDetail, getStyleForTheme) | ✅ Selesai |

**Urutan:** Tahap 2 (GeocodingService) sebaiknya sebelum Tahap 3, karena autocomplete memakai geocoding.

---

## 1. Load Icon Mobil (Tumpang Tindih Tinggi)

**3 implementasi terpisah** dengan logika serupa (~50–90 baris masing-masing):

| File | Method | Perbedaan |
|------|--------|-----------|
| `driver_screen.dart` | `_loadCarIconsOnce()` | Responsive.iconSize(52), decodeWidth 96–186 |
| `penumpang_screen.dart` | `_loadCarIcons()` | baseSize 50, simpan `_carImageRed/Green` untuk komposit nama |
| `passenger_track_map_widget.dart` | `_loadCarIcons()` | size 80, padding 12, decodeWidth 160–280 |

**Alur sama:** load PNG → instantiateImageCodec → canvas + padding → BitmapDescriptor.bytes

**Implementasi:** ✅ `lib/services/car_icon_service.dart` – CarIconService dengan CarIconResult (red, green, redImage, greenImage). Lihat `docs/REFACTOR_7_TAHAP.md` Tahap 2.

---

## 2. Autocomplete Tujuan (Geocode + Placemark)

**Logika hampir identik** di 2 file besar:

| File | Method | Baris |
|------|--------|-------|
| `driver_screen.dart` | `_onDestChanged` (dalam `_RouteFormBottomSheet`) | ~120 baris |
| `penumpang_screen.dart` | `_onDestChanged` | ~100 baris |

**Alur sama:**
1. `locationFromAddress(query + ", Indonesia")`
2. Deduplikasi koordinat
3. (driver) Sort by distance dari driver
4. `placemarkFromCoordinates` untuk tiap lokasi
5. (driver) Filter provinsi sesama pulau
6. Set `_autocompleteResults`, `_autocompleteLocations`
7. `Scrollable.ensureVisible`, `animateCamera`

**Perbedaan:** driver punya `sameProvinceOnly`, `sameIslandOnly`, `provincesInIsland`.

**Rekomendasi:** Ekstrak ke `GeocodeAutocompleteService` atau widget `DestinationAutocompleteField` yang reusable.

---

## 3. Geocoding Pattern (locationFromAddress + placemarkFromCoordinates)

**Digunakan di 6+ file** dengan pola serupa:

| File | Use case |
|------|----------|
| `driver_screen.dart` | Form asal/tujuan, autocomplete |
| `penumpang_screen.dart` | Form tujuan, autocomplete |
| `pesan_screen.dart` | Search asal & tujuan (2 method) |
| `driver_jadwal_rute_screen.dart` | Autocomplete asal & tujuan |
| `cari_travel_screen.dart` | Geocode tujuan |
| `scheduled_drivers_service.dart` | Geocode asal & tujuan |

**Rekomendasi:** Centralize di `GeocodingService` (lihat `docs/4_TAHAP_GEOCODING.md` Tahap 2).

---

## 4. Wrapper _formatPlacemarkDetail (Minor)

**Duplikat trivial** di 2 file:

```dart
// driver_screen.dart & penumpang_screen.dart
String _formatPlacemarkDetail(Placemark p) => PlacemarkFormatter.formatDetail(p);
```

**Implementasi:** ✅ Hapus wrapper, panggil `PlacemarkFormatter.formatDetail` langsung. Juga hapus `getStyleForTheme` dari MapStyleService. Lihat `docs/REFACTOR_7_TAHAP.md` Tahap 4.

---

## 5. Chat Message Building (Tumpang Tindih Tinggi)

**Duplikat ~400 baris** di 2 file:
- `chat_room_penumpang_screen.dart` – _buildBarcodeMessage, _buildTextContent, _buildAudioMessage, _buildImageMessage, _buildVideoMessage
- `chat_driver_screen.dart` – implementasi hampir identik

**Implementasi:** ✅ `lib/widgets/chat_message_content.dart` – ChatMessageContent. Lihat `docs/REFACTOR_7_TAHAP.md` Tahap 5.

---

## 6. Yang Bukan Tumpang Tindih

| Item | Keterangan |
|------|------------|
| **DataOrderScreen vs DataOrderDriverScreen** | Berbeda role: penumpang vs driver |
| **CekLokasiBarang vs CekLokasiDriver** | Sama-sama pakai `PassengerTrackMapWidget` (shared) |
| **ChatRoomPenumpangScreen vs ChatPenumpangScreen** | Berbeda: room tunggal vs daftar chat |
| **MapStyleService** | Sudah terpusat, dipakai konsisten |

---

## Ringkasan Prioritas Refactor

| Tahap | Item | Status | Dampak |
|-------|------|--------|--------|
| 1 | CarIconService | ✅ | Kurangi ~150 baris duplikat |
| 2 | GeocodingService (centralize) | ✅ | Persiapan 4_TAHAP_GEOCODING Tahap 2 |
| 3 | DestinationAutocompleteService | ✅ | Kurangi ~200 baris, konsistensi UX |
| 4 | Hapus _formatPlacemarkDetail, getStyleForTheme | ✅ | Minor cleanup |
| 5 | ChatMessageContent | ✅ | Kurangi ~400 baris duplikat chat |

**Dokumen lengkap 7 tahap audit:** `docs/REFACTOR_7_TAHAP.md`
