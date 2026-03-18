# Performance Audit – Traka

Ringkasan audit performa dan referensi dokumen optimasi.

---

## Status Audit

| Area | Status | Dokumen |
|------|--------|---------|
| RAM 4GB | ✅ Implementasi | OPTIMASI_PERFORMA_RAM_4GB.md |
| Build speed | ✅ Implementasi | OPTIMASI_BUILD_SPEED.md |
| Geocoding | ⏳ | 4_TAHAP_GEOCODING.md (debounce, cache) |

---

## Checklist Performa

### 1. Image & Cache
- [x] CachedNetworkImage untuk foto profil, driver, dll.
- [x] CarIconService decode PNG dengan ukuran terbatas (targetWidth)
- [ ] Kompresi gambar sebelum upload (opsional)

### 2. List & Scroll
- [x] ListView cacheExtent 100–200px
- [x] Cari Travel: cluster manager untuk marker
- [ ] Pagination untuk list panjang (opsional)

### 3. Lokasi & Map
- [x] Update lokasi 15 detik (bukan 10)
- [x] Threshold camera 20m (penumpang) / 10m (driver)
- [x] Max 5 hasil autocomplete, debounce 800ms
- [x] Directions API cache di DirectionsService

### 4. Error & Logging
- [x] logError → Crashlytics (non-fatal) di release
- [x] Catch block critical path memakai logError

### 5. Loading UX
- [x] ShimmerLoading untuk list loading (Data Order, Cari Travel)
- [x] CircularProgressIndicator untuk aksi singkat (submit, scan)

---

## Rekomendasi

1. **Perangkat rendah RAM:** Gunakan LowRamWarningService; kurangi jumlah marker simultan.
2. **Geocoding:** Implementasi Tahap 2–4 dari 4_TAHAP_GEOCODING (fallback API, Places Autocomplete, cache).
3. **Dispose:** Pastikan StreamSubscription, Timer, controller di-dispose di `dispose()`.
4. **Profil:** Periksa Flutter DevTools (Performance) untuk jank dan frame drop.

---

## Referensi

- **OPTIMASI_PERFORMA_RAM_4GB.md** – Detail optimasi RAM
- **OPTIMASI_BUILD_SPEED.md** – Gradle build
- **4_TAHAP_GEOCODING.md** – Geocoding debounce, cache
