# UX Lacak Driver & Lacak Barang

## Perbandingan: Shopee vs Traka

### Shopee (Cek Pesanan)
- Icon mobil **diam**, lalu **loncat-loncat** ke posisi baru
- Tidak real-time / tidak smooth

### Traka (Lacak Barang)
- Icon mobil **real-time** mengikuti posisi driver
- Rute awal (polyline) tampil
- **Asal:** pin + foto profil pengirim
- **Tujuan:** pin + foto profil penerima

### Traka (Lacak Driver)
- Icon mobil mengarah ke penumpang
- **Penumpang:** pin/icon + foto profil

---

## Ringkasan Fitur Traka

| Fitur | Lacak Barang | Lacak Driver |
|-------|--------------|--------------|
| Posisi driver | Real-time | Real-time |
| Polyline rute | ✓ | ✓ |
| Pin asal | Pin + foto profil pengirim | - |
| Pin tujuan | Pin + foto profil penerima | - |
| Pin penumpang | - | Pin + foto profil penumpang |
| Arah icon mobil | Ke tujuan | Ke penumpang |

---

## Implementasi

| Komponen | File |
|----------|------|
| Service pin + foto profil | `lib/services/marker_icon_service.dart` |
| Lacak Barang | `lib/screens/cek_lokasi_barang_screen.dart` |
| Lacak Driver | `lib/screens/cek_lokasi_driver_screen.dart` |
| Widget map shared | `lib/widgets/passenger_track_map_widget.dart` |
