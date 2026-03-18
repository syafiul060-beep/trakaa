# Jarak Kapal Laut (Pengurangan dari Kontribusi)

## Ringkasan

Untuk rute yang melewati kapal laut (antar pulau), jarak naik kapal **tidak dihitung** dalam perhitungan kontribusi. Hanya jarak darat yang dikenakan tarif.

---

## Alur (Hybrid: Estimasi Otomatis + Manual)

1. **Saat scan selesai** (penumpang scan barcode driver / penerima scan barcode driver)
2. Sistem ambil koordinat pickup dari order dan drop dari GPS
3. **Jika sama pulau** (estimasi = null): lewati dialog, `ferryDistanceKm = 0`
4. **Jika beda pulau** (estimasi ada): muncul dialog dengan:
   - Teks: "Estimasi jarak kapal: X km"
   - Tombol **[Gunakan]** → pakai estimasi
   - Tombol **[Ubah]** → input manual
   - Tombol **[Lewati]** → tidak ada pengurangan
5. Jika tidak ada estimasi (koordinat tidak lengkap): dialog manual seperti sebelumnya

---

## Perhitungan

- `jarak_efektif = max(0, tripDistanceKm - ferryDistanceKm)`
- **Travel:** `tripFareRupiah = jarak_efektif × tarifPerKm`
- **Kirim barang:** `tripBarangFareRupiah = jarak_efektif × tarifBarangPerKm`

---

## Estimasi Otomatis (FerryDistanceService)

- Provinsi asal/tujuan dari koordinat via `LacakBarangService.getProvinceFromLatLng`
- Pulau dari `ProvinceIsland.getIslandForProvince`
- Jika beda pulau: cari di Firestore `app_config/ferry_distances` atau fallback ke default

### Konfigurasi Firestore: `app_config/ferry_distances`

Override estimasi per pasangan pulau. Key: `"Pulau1_Pulau2"` (alfabetis). Contoh: `Jawa_Sumatera` (25 km), `Bali & Nusa Tenggara_Jawa` (3 km).

| Field | Tipe | Keterangan |
|-------|------|------------|
| `Jawa_Sumatera`, `Bali & Nusa Tenggara_Jawa`, dll. | number | Jarak ferry (km) untuk pengurangan kontribusi |
| `durations` | Map | Durasi ferry (jam) per pasangan pulau untuk ETA Lacak Barang. Contoh: `{ "Jawa_Sumatera": 2.0 }` |

---

## Lacak Barang: Driver di Kapal Laut

Fitur deteksi otomatis saat driver diperkirakan sedang di kapal laut (rute antar pulau).

### Cara Kerja

1. **Kondisi:** Rute pickup–drop beda pulau, jarak total ≥ 40 km, posisi driver dalam radius 25 km dari titik tengah rute.
2. **Inferensi:** Sistem menganggap driver di kapal laut.
3. **UI:** Icon kapal (`ship_icon.png`), teks "Driver sedang di kapal laut", ETA tiba di pelabuhan tujuan, label rute (mis. Jawa – Sumatera).

### Konfigurasi

- **Asset:** `assets/images/ship_icon.png` (fallback: marker biru jika tidak ada).
- **Durasi ETA:** Dari Firestore `app_config/ferry_distances` → field `durations` (Map). Key = pasangan pulau (alfabetis), value = jam. Contoh: `{ "durations": { "Jawa_Sumatera": 2.0 } }`.
- **Parameter deteksi:** `_detectionRadiusKm = 25`, `_minRouteKm = 40` (di `FerryDistanceService`).

### File Terkait

| File | Fungsi |
|------|--------|
| `ferry_distance_service.dart` | `FerryStatus`, `checkDriverOnFerry`, durasi ferry |
| `passenger_track_map_widget.dart` | `enableFerryDetection`, icon kapal, debounce 8 detik |
| `cek_lokasi_barang_screen.dart` | UI status ferry di Lacak Barang |

---

## Field

| Field | Lokasi | Keterangan |
|-------|--------|------------|
| `ferryDistanceKm` | orders | Jarak kapal (km) yang dikurangi |

---

## Catatan

- **Scan barcode:** Dialog ferry (hybrid) muncul sebelum order selesai jika beda pulau.
- **Auto-complete** (completeOrderWhenFarApart): Tidak ada input ferry; seluruh jarak dihitung.
- **Validasi:** `ferryDistanceKm` dibatasi `>= 0`; tidak boleh melebihi `tripDistanceKm` (anti-kecurangan).
