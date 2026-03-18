# 4 Tahap Pembaharuan Geocoding

Ringkasan tahap perbaikan geocoding (alamat ↔ koordinat, cari lokasi) untuk cakupan Indonesia yang lebih baik—desa, kecamatan, jalan kecil.

---

## Status

| Tahap | Deskripsi | Status |
|-------|-----------|--------|
| **1** | Tetap pakai native, pantau feedback | ✅ Berjalan |
| **1b** | GeocodingService (centralize) | ✅ Selesai |
| **2** | Google Geocoding API sebagai fallback | ⏳ Belum |
| **3** | Google Places Autocomplete untuk search | ⏳ Belum |
| **4** | Optimasi: debounce, cache, rate limit | ⏳ Belum |

---

## Detail

### Tahap 1: Native + monitoring
- **Saat ini:** Package `geocoding` (Android Geocoder, iOS CLGeocoder)
- **Implementasi:** `locationFromAddress()`, `placemarkFromCoordinates()`
- **PlacemarkFormatter:** `thoroughfare`, `subLocality` (desa), `locality` (kecamatan)
- **Optimasi:** Suffix `", Indonesia"` pada query
- **Tindakan:** Pantau laporan user (lokasi tidak ditemukan, hasil salah)

### Tahap 2: Google Geocoding API fallback
- **Tujuan:** Cakupan lebih baik untuk desa, kecamatan, jalan kecil
- **Implementasi:** Service baru memanggil `https://maps.googleapis.com/maps/api/geocode/json`
- **Fallback:** Jika API gagal/limit → tetap pakai native
- **API key:** gunakan `MapsConfig.directionsApiKey` (atau key terpisah)
- **Kuota:** Gratis ~40.000 req/bulan

### Tahap 3: Google Places Autocomplete
- **Tujuan:** Cari lokasi lebih relevan saat user mengetik
- **Implementasi:** Places Autocomplete API atau Places SDK
- **Use case:** Form asal/tujuan, autocomplete search
- **Dependency:** `google_places_flutter` atau HTTP ke Places API

### Tahap 4: Optimasi
- **Debounce:** Batasi panggilan geocode saat user mengetik (mis. 300 ms)
- **Cache:** Simpan hasil geocode untuk query/koordinat yang sama
- **Rate limit:** Jaga agar tidak melebihi kuota API
- **Lihat:** `docs/OPTIMASI_PERFORMA_RAM_4GB.md` (throttle geocoding)

---

## File Terkait

| File | Peran |
|------|--------|
| `lib/utils/placemark_formatter.dart` | Format alamat Indonesia |
| `lib/config/province_island.dart` | Provinsi & pulau |
| `lib/screens/driver_screen.dart` | Geocode form asal/tujuan |
| `lib/screens/penumpang_screen.dart` | Geocode form tujuan |
| `lib/screens/cari_travel_screen.dart` | Geocode tujuan |
| `lib/screens/pesan_screen.dart` | Geocode asal/tujuan |
| `lib/services/location_service.dart` | Reverse geocode validasi driver |

---

## Referensi

- **Geocoding API:** https://developers.google.com/maps/documentation/geocoding
- **Places Autocomplete:** https://developers.google.com/maps/documentation/places/web-service/autocomplete
- **Package geocoding:** https://pub.dev/packages/geocoding
- **API key:** `docs/API_KEY_PRODUCTION.md` (Geocoding API)
