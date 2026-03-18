# Pelacakan Driver & Barang ala Gojek/Grab

Dokumen ini menjelaskan perbandingan Traka dengan Gojek/Grab dan perbaikan yang telah diimplementasikan.

## Fitur Gojek/Grab yang Diacu

### Pelacakan Driver (GoRide / GrabCar)
- **Marker hijau** posisi driver di peta
- **Rute** dari driver ke titik jemput/tujuan
- **Update real-time** setiap beberapa detik (polling API)
- **Snap to road** – proyeksi GPS ke jalan agar ikon tidak "terbang"
- **Animasi halus** – ikon bergerak mengikuti rute, bukan loncat
- **ETA** dinamis berdasarkan kecepatan aktual

### Pelacakan Barang (GoSend / GrabExpress)
- Sama seperti ride: live tracking di peta
- Status: driver menuju pickup → paket diambil → dalam perjalanan → sampai

---

## Yang Sudah Ada di Traka

| Fitur | Status |
|-------|--------|
| Snap to road (projectPointOntoPolyline) | ✅ |
| Interpolasi sepanjang rute | ✅ |
| Kamera tilt 3D, mobil di bawah | ✅ |
| pointAheadOnPolyline untuk target kamera | ✅ |
| Icon mobil merah/hijau | ✅ |
| Stream Firestore untuk Lacak Driver/Barang | ✅ |
| ETA dinamis dari kecepatan aktual | ✅ |

---

## Perbaikan yang Diimplementasikan

### 1. Update Lokasi Lebih Sering (Live Tracking)

**Masalah:** Driver hanya update ke Firestore setiap **2 km** atau **15 menit**. Penumpang melihat posisi yang sangat tertinggal.

**Solusi:** Saat driver menuju jemput atau dalam perjalanan dengan penumpang/barang, update lebih sering:
- **50 meter** perpindahan, atau
- **10 detik** sejak update terakhir

**File:** `driver_status_service.dart`, `driver_screen.dart`

**Kondisi live tracking:**
- `_navigatingToOrderId != null` – driver menuju jemput penumpang/pengirim
- `_jumlahPenumpangPickedUp > 0` – ada penumpang travel di mobil
- `_jumlahBarang > 0` – ada order barang aktif (pickup/delivery)

### 2. Icon Mobil Muncul Lebih Cepat

- Load icon di awal `initState` (tanpa delay)
- Fallback merah/hijau (bukan biru) saat icon belum selesai load

### 3. Default Map Type Normal

- Driver & penumpang: default `MapType.normal` (peta jalan)

---

## Perbandingan Update Frequency

| Mode | Sebelum | Sesudah |
|------|---------|---------|
| Rute biasa (tanpa penumpang/barang) | 2 km / 15 min | 2 km / 15 min |
| Menuju jemput / dalam perjalanan | 2 km / 15 min | **50 m / 5 detik** |

---

## Catatan Biaya

Update lebih sering = lebih banyak Firestore writes. Mode live tracking hanya aktif saat:
- Driver diarahkan ke penumpang (navigating to pickup), atau
- Ada penumpang/barang di mobil (dalam perjalanan)

Saat driver bekerja tanpa order aktif, tetap pakai mode hemat (2 km / 15 min).
