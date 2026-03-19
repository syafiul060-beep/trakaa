# Konsep Multi-Penumpang & Route Optimasi (Traka)

Dokumen referensi untuk fitur driver mode: multi penumpang, kirim barang, dan optimasi rute ala Grab/Gojek.

---

## 1. Konsep Utama

Traka bukan ride-hailing biasa—ini **Hybrid Mobility + Logistics Platform**:

- **Multi penumpang** – naik/turun bebas di mana saja
- **Kirim barang** – delivery dalam perjalanan
- **Kapasitas kendaraan** – sesuai kesepakatan / kapasitas mobil
- **Tujuan driver** – tetap ada (bukan random)

---

## 2. Status Penumpang & Barang

| Status | Keterangan | Tampil di Map |
|-------|------------|---------------|
| `waitingPickup` | Belum dijemput | Ya (icon kuning) |
| `onTrip` | Sudah naik / barang di mobil | Ya (icon hijau/biru) |
| `completed` | Sudah turun / barang sampai | Tidak |

---

## 3. Tampilan Map (Beranda Driver)

### Saat driver aktif

- **Posisi driver** – icon arrow (bergerak) / dot (diam)
- **Penumpang** – sesuai kesepakatan atau kapasitas mobil (bukan cuma 1–2)
- **Marker logic:**

| Tipe | Icon | Warna |
|------|------|-------|
| Driver | Arrow / dot | Biru |
| Pickup (belum dijemput) | Titik / pin | Kuning |
| Dropoff (sudah naik) | Titik / pin | Hijau |
| Completed | — | Tidak tampil |

### Interaksi

- **Klik penumpang di map** → navigasi ke lokasi penjemputan
- **Klik di panel/list beranda** → fokus map + navigasi ke lokasi
- **Setelah dijemput** → status berubah, masuk list pengantaran
- **Setelah sampai** → hilang dari map dan list

---

## 4. Flow Sistem

```
Driver online
    ↓
Load semua penumpang (sesuai kesepakatan/kapasitas)
    ↓
Tampilkan di map
    ↓
Driver klik / auto pilih target
    ↓
Navigasi ke pickup
    ↓
Pickup → status berubah (waitingPickup → onTrip)
    ↓
Navigasi ke berikutnya (dropoff terdekat / tujuan driver)
    ↓
Dropoff → completed → hilang dari map
    ↓
Ulangi sampai tidak ada lagi stop
```

### Prioritas target

1. **Pickup terdekat** – penumpang/barang belum dijemput
2. **Dropoff terdekat** – penumpang/barang sudah di mobil
3. **Tujuan driver** – jika tidak ada pickup/dropoff lagi

---

## 5. Model Data (#1 – Mapping ke Firestore)

### Konsep Stop (unified)

```dart
enum StopType { pickup, dropoff }

// Stop = satu titik kunjungan (pickup atau dropoff dari satu order)
```

### Mapping OrderModel (Firestore) → Stop

| Stop | OrderModel field | Keterangan |
|------|------------------|-------------|
| **Pickup** | `passengerLat/Lng` atau `originLat/Lng` | Lokasi jemput penumpang/pengirim |
| **Dropoff** | `destLat/Lng` atau `receiverLat/Lng` | Tujuan penumpang/lokasi penerima |
| **Status** | `status`: agreed → pickup, picked_up → dropoff, completed → hilang | |

### Status OrderModel ↔ Konsep

| Firestore status | Konsep | Tampil |
|------------------|--------|--------|
| `agreed` | waitingPickup | Ya (pickup) |
| `picked_up` | onTrip | Ya (dropoff) |
| `completed` | completed | Tidak |

### Load (kapasitas)

- Travel: 1 orang (atau +jumlahKerabat)
- Kirim barang: 1 slot (dokumen) atau berdasarkan berat/volume (kargo)

---

## 6. Routing System

### Multi waypoint

Route = urutan stop:

```
Driver → A (pickup) → B (pickup) → C (drop A) → D (drop B) → Tujuan driver
```

### Constraint

- **Kapasitas:** `currentLoad + stop.load <= maxCapacity`
- **Urutan:** pickup HARUS sebelum dropoff untuk order yang sama

---

## 7. Prioritas Implementasi

Urutan yang **paling masuk akal** untuk diimplementasikan:

| # | Fitur | Alasan |
|---|-------|--------|
| **1** | **Dokumentasi & model data** | Fondasi—pastikan enum, class, dan flow jelas |
| **2** | **Tampilkan multi penumpang di map** | UX inti—driver lihat siapa saja yang perlu dijemput/diantar |
| **3** | **Klik penumpang → navigasi** | Interaksi dasar—driver bisa pilih target |
| **4** | **Prioritas target (pickup → dropoff → tujuan)** | Logic routing—urutan stop yang benar |
| **5** | **Update status (pickup → onTrip → completed)** | State management—marker & list ikut berubah |
| **6** | **Panel list penumpang di beranda** | UX—driver bisa pilih dari list, bukan cuma map |
| **7** | **Greedy route optimization** | Efisiensi—urutan stop berdasarkan jarak terdekat |
| **8** | **Insert optimization (order baru)** | Level lanjut—saat order baru masuk, cari posisi terbaik di route |
| **9** | **Backend matching (Redis GEO)** | Skala—cari driver terdekat, hitung cost |

---

## 8. Algoritma Optimasi (Ringkas)

### Greedy (baseline)

```dart
// Urutkan stop berdasarkan jarak dari posisi saat ini
stops.sort((a, b) => distance(current, a.location)
    .compareTo(distance(current, b.location)));
```

### Insert optimization (order baru)

- Coba semua posisi insert pickup + dropoff
- Validasi: kapasitas, pickup sebelum dropoff
- Pilih route dengan cost terkecil (jarak + delay)

---

## 9. Backend Realtime (Opsional, Skala Besar)

| Komponen | Peran |
|----------|-------|
| **Redis GEO** | Lokasi driver, cari terdekat |
| **Pub/Sub** | Event realtime (order baru, update status) |
| **API Server** | Matching, routing, validasi |

---

## 10. File Terkait (Traka Saat Ini)

- `lib/screens/driver_screen.dart` – beranda driver, map, navigasi
- `lib/services/directions_service.dart` – API rute
- `lib/services/route_utils.dart` – polyline, snap to road
- `lib/models/order_model.dart` – model order
- `docs/KIRIM_BARANG_FLOW.md` – alur kirim barang
- `docs/RENCANA_NAVIGASI_DRIVER.md` – parameter kamera & map

---

## 11. Langkah Next

1. **Review model Order/Stop** – sesuaikan dengan Firestore yang ada
2. ~~**Implementasi #2** – tampilkan marker penumpang di map~~ ✅ **Selesai**
3. **Implementasi #3** – klik marker → navigasi ke lokasi (✅ sudah: tap pickup → dialog "Ya, arahkan"; tap dropoff → langsung navigasi)
4. ~~**Implementasi #4** – logic prioritas target~~ ✅ **Selesai** (banner "Arahkan ke stop terdekat", pickup → dropoff → tujuan)
5. ~~**Implementasi #5** – update status saat pickup/dropoff~~ ✅ **Selesai** (auto-transisi pickup→dropoff saat scan; completed hilang dari map)
6. ~~**Implementasi #6** – panel list penumpang di beranda~~ ✅ **Selesai** (DriverStopsListOverlay: gabungan Penjemputan + Pengantaran, tap → fokus map + navigasi)
7. ~~**Implementasi #7** – Greedy route optimization~~ ✅ **Selesai** (RouteOptimizationService: urutan stop berdasarkan jarak terdekat)

## 12. Langkah Next (setelah #7)

8. ~~**Insert optimization (order baru)**~~ ✅ **Selesai** (RouteOptimizationService + terintegrasi di driver_screen)
9. ~~**Backend matching (Redis GEO)**~~ ✅ **Dokumentasi** (traka-api/docs/REDIS_GEO_MATCHING.md)

---

*Dokumen ini disusun berdasarkan konsep Traka: travel penumpang multi-stop + kirim barang.*
