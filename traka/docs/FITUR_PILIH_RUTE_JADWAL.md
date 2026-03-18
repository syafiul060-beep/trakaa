# Fitur Pilih Rute di Jadwal Terjadwal

## Ringkasan

Driver dapat memilih rute spesifik saat membuat jadwal. Rute yang dipilih:
1. **Disimpan** untuk pencarian penumpang (hanya penumpang yang asal-tujuannya melewati rute itu yang muncul)
2. **Pre-load** saat driver klik "Rute" di jadwal (langsung siap, tanpa pilih lagi)

## Alur

### 1. Form Jadwal (Baru/Edit)

- Driver isi tujuan awal, tujuan akhir, jam
- Tombol **"Lihat dan pilih rute"** → bottom sheet daftar rute alternatif (Rute 1, 2, 3…)
- Driver pilih satu rute → disimpan
- Simpan jadwal → `routePolyline` tersimpan di Firebase

### 2. Klik "Rute" di Card Jadwal

- **Jika rute tersimpan:** Beranda langsung tampil dengan rute terpilih. Snackbar: "Rute sudah dipilih. Tap Mulai Rute ini untuk mulai bekerja."
- **Jika belum:** Beranda tampil pilihan rute (perilaku lama).

### 3. Pencarian Penumpang (Pesan nanti)

- **Jika jadwal punya routePolyline:** Hanya penumpang yang asal-tujuannya melewati rute itu yang muncul.
- **Jika tidak:** Fallback ke perilaku lama (cek semua alternatif).
- **Jadwal lama** (tanpa routePolyline): tetap pakai fallback.

## Struktur Data Firebase

`driver_schedules/{uid}` → `schedules` (array) → item:

```json
{
  "origin": "...",
  "destination": "...",
  "departureTime": Timestamp,
  "date": Timestamp,
  "routePolyline": [{"lat": -6.xxx, "lng": 106.xxx}, ...]
}
```

`routePolyline` opsional. Backward compatible.

## Edit Jadwal

- Jika origin/destination diubah → rute di-reset (driver harus pilih lagi).
- Jika tidak diubah → rute tetap.

## File Terkait

| File | Peran |
|------|------|
| `lib/screens/driver_jadwal_rute_screen.dart` | Form jadwal, pilih rute, simpan routePolyline |
| `lib/screens/driver_screen.dart` | Load rute dari jadwal, pre-select jika tersimpan |
| `lib/services/scheduled_drivers_service.dart` | Matching penumpang pakai routePolyline |
| `lib/widgets/driver_map_overlays.dart` | routeColorForIndex untuk sheet pilih rute |
