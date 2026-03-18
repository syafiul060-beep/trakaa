# Rencana Navigasi Driver

Dokumen referensi parameter dan perilaku navigasi di Beranda driver.

---

## Parameter Kamera

| Parameter | Nilai | Keterangan |
|-----------|-------|-------------|
| Zoom | 18 | Lebih banyak jalan terlihat (500 m look-ahead) |
| Tilt | 58° | Sudut pandang 3D |
| Look-ahead | 500 m | Target kamera di depan |
| maxDistanceMeters | 600 | Proyeksi posisi ke polyline |

---

## Perilaku Peta

| Kondisi | Perilaku |
|---------|----------|
| **Jalan lurus** | Peta bergerak menurun (target bergeser ke depan) |
| **Belok kiri/kanan** | Peta berputar sesuai arah rute (bearing dari polyline) |
| **Berhenti** | Skip animasi jika target < 3 m (peta stabil) |

---

## Icon Lokasi

| Kondisi | Bentuk | Ukuran |
|---------|--------|--------|
| Diam | Titik biru | 24–36 px (responsif) |
| Bergerak | Segitiga biru dalam oval putih | 48–72 px (responsif) |

---

## Update & Animasi

| Aspek | Nilai |
|-------|-------|
| GPS (saat bekerja) | 2 detik |
| GPS (tidak bekerja) | 30 detik |
| Bearing hysteresis | 3° |
| Bearing smooth alpha | 0.2 |
| Durasi animasi kamera | 250–1100 ms (proporsional jarak) |

---

## File Terkait

- `lib/screens/driver_screen.dart` – logika utama
- `lib/widgets/driver_location_overlay.dart` – overlay titik/segitiga
- `lib/services/driver_location_icon_service.dart` – titik biru marker
- `lib/widgets/passenger_track_map_widget.dart` – Lacak Driver (parameter sama)

---

## Posisi Overlay

- Titik/panah biru di **tengah horizontal** (lurus dengan icon Chat di bottom nav)
- Map padding = 0 agar center peta = center layar = center overlay

## Snap ke Rute

- Posisi tampilan di-proyeksikan ke polyline (max 150 m dari jalan)
- Titik/panah tersinkron dengan garis biru sampai tujuan
- Jika > 150 m dari rute: fallback ke posisi GPS mentah

## Warna Rute Dinamis

- **Sudah dilewati:** kuning (amber)
- **Belum dilewati:** biru (primary) / hijau (rute ke penumpang)

## Re-routing

- Saat keluar rute (> 150 m): garis biru ke jalan lain untuk kembali
- Main route: re-fetch dari posisi saat ini ke tujuan (debounce 30s / 100m)
- Rute ke penumpang: re-fetch saat keluar rute (debounce 100m)

## Cara Uji

1. **Posisi:** Pastikan titik biru lurus dengan icon Chat.
2. **Jalan lurus:** Pastikan peta bergerak menurun, icon tetap di bawah.
3. **Belok:** Pastikan peta berputar mengikuti arah jalan.
4. **Berhenti:** Pastikan peta stabil, tidak bergoyang.
5. **Lokasi:** Titik biru = posisi GPS driver (map mengikuti rute biru).
