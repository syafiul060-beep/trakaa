# Refactor 7 Tahap (Audit)

Ringkasan refactoring yang dilakukan berdasarkan audit kode Traka.

---

## Status

| Tahap | Deskripsi | Status |
|-------|-----------|--------|
| **1** | Dead code & bug (AdminChatService, null check cluster) | ✅ Selesai |
| **2** | CarIconService – load icon mobil terpusat | ✅ Selesai |
| **3** | StyledGoogleMapBuilder, night mode offline map | ✅ Selesai |
| **4** | Hapus wrapper _formatPlacemarkDetail, getStyleForTheme | ✅ Selesai |
| **5** | ChatMessageContent – widget pesan chat terpusat | ✅ Selesai |
| **6** | Update dokumentasi | ✅ Selesai |
| **7** | Konsistensi LocationService | ✅ Selesai |

---

## Detail Per Tahap

### Tahap 1: Dead code & bug
- **Hapus:** `lib/services/admin_chat_service.dart` (dead code)
- **Perbaikan:** `cari_travel_screen.dart` – null check `toByteData()` di `_buildClusterIcon()`, fallback ke `BitmapDescriptor.defaultMarkerWithHue`

### Tahap 2: CarIconService
- **File baru:** `lib/services/car_icon_service.dart`
- **CarIconResult:** red, green, redImage, greenImage
- **Migrasi:** driver_screen, penumpang_screen, passenger_track_map_widget, data_order_driver_screen
- **Lihat:** `docs/ASSET_ICON_MOBIL.md`, `docs/4_TAHAP_ICON_MOBIL.md`

### Tahap 3: StyledGoogleMapBuilder & night mode
- **File baru:** `lib/widgets/styled_google_map_builder.dart`
- **Migrasi:** cari_travel_screen, penumpang_screen, driver_screen, passenger_track_map_widget, data_order_driver_screen
- **Night mode offline:** `offline_map_screen.dart` pakai `MapStyleService.themeNotifier` + `isNightTimeNotifier` (18:00–06:00)

### Tahap 4: Hapus wrapper
- **_formatPlacemarkDetail:** Ganti dengan `PlacemarkFormatter.formatDetail()` langsung di driver_screen, penumpang_screen
- **_formatPlacemark:** Hapus dari driver_screen
- **getStyleForTheme:** Hapus dari MapStyleService (dead code, pakai getStyleForMap)

### Tahap 5: ChatMessageContent
- **File baru:** `lib/widgets/chat_message_content.dart`
- **Migrasi:** chat_room_penumpang_screen, chat_driver_screen
- **Konten:** teks, audio, gambar, video, barcode
- **Parameter:** barcodeSnippet berbeda (penumpang: "Scan di Data Order", driver: "Tampilkan di Data Order untuk di-scan penumpang")

### Tahap 6: Update dokumentasi
- **File ini:** `docs/REFACTOR_7_TAHAP.md`
- **Update:** `ANALISIS_TUMPANG_TINDIH.md`, `4_TAHAP_ICON_MOBIL.md`, `OFFLINE_MAP.md`

### Tahap 7: Konsistensi LocationService
- **getCurrentPositionWithMockCheck** (flow kritis, cek fake GPS): data_order_driver_screen (auto-confirm, auto-complete, cancel), data_order_screen (auto-complete, cancel), driver_jadwal_rute_screen, scan_transfer_driver_screen, sos_service
- **getCurrentPosition** (display only): offline_map_screen, cari_travel_screen, data_order_driver_screen (map pengirim/penerima, map driver/penumpang)
- Flow kritis: jika fake GPS terdeteksi → abort (tidak auto-confirm, tidak kirim lokasi palsu)

---

## File Terkait

| Widget/Service | File |
|----------------|------|
| StyledGoogleMapBuilder | `lib/widgets/styled_google_map_builder.dart` |
| ChatMessageContent | `lib/widgets/chat_message_content.dart` |
| CarIconService | `lib/services/car_icon_service.dart` |
| MapStyleService | `lib/services/map_style_service.dart` |
