# Rute alternatif driver & matching penumpang (referensi produk)

Dokumen ini menjawab: **kapan garis biru / indeks rute berubah**, **apa yang terjadi jika driver menyimpang**, dan **bagaimana penumpang yang mencari driver aktif difilter** — mengacu perilaku kode saat ini.

---

## 1. Ringkas (untuk CS / QA)

| Pertanyaan | Jawaban singkat |
|------------|-----------------|
| Driver pilih rute A lalu jalan di koridor rute B? | Jika GPS **lebih dekat** ke polyline alternatif lain (dalam toleransi, lihat §3), setelah **jeda waktu** sistem bisa **auto-switch** ke rute B dan memperbarui status ke Firestore. |
| Driver keluar sama sekali dari semua garis (jalan tikus / off-route)? | **Re-route** dari posisi sekarang ke tujuan (debounce), snackbar “Rute diperbarui…”, polyline utama diganti; **bukan** memaksa kembali ke rute A. |
| Penumpang “cari driver” — apakah harus sama dengan rute yang dipilih driver di HP? | **Tidak.** Filter memakai **semua alternatif** dari Directions (asal→tujuan driver) + aturan lokasi penumpang; **bukan** mengunci pada satu indeks yang ditap driver. |
| API `/api/match/drivers` memakai indeks rute? | **Tidak.** Geo + status + (opsional) skor **arah** vs tujuan penumpang vs ujung rute driver + kapasitas + kebaruan lokasi. |
| Mode aktif, **bukan** navigasi jemput — lewat gang/pedesan, keluar biru? | Banner off-route jika GPS **> ~350 m** dari polyline; setelah debounce → **re-route** dari posisi sekarang ke tujuan (SnackBar). Lihat §2.3. |

---

## 2. Driver — setelah pilih rute alternatif

### 2.1 Garis navigasi (polyline utama)

- Yang dipilih user disimpan sebagai **`_selectedRouteIndex`** + **`_routePolyline`** dari daftar **`_alternativeRoutes`** (hasil Directions).
- **Auto-switch** (`_checkAndAutoSwitchRoute` di `lib/screens/driver_screen.dart`):
  - Dari posisi GPS, dihitung **rute alternatif mana yang jarak tegaknya paling kecil** (`RouteUtils.findNearestRouteIndex`).
  - Hanya kandidat dengan jarak tegak **≤ `_autoSwitchNearestRouteToleranceMeters`** (produksi: **500 m**).
  - Jika indeks terdekat **bukan** rute yang sedang dipilih, dan sudah **≥ `_autoSwitchRouteCooldown`** (produksi: **10 menit**) sejak switch terakhir → **switch** ke rute terdekat, update polyline + **`DriverStatusService.updateDriverStatus`** (termasuk `routeSelectedIndex`).
  - Jika driver **kembali** ke koridor rute “asal” yang disimpan (`_originalRouteIndex`), dengan aturan waktu serupa, bisa **switch balik**.
- **Re-route off-route** (`_maybeRerouteFromCurrentPosition`):
  - Dipicu saat proyeksi GPS ke polyline menganggap **off-route** (lihat alur `targetSeg` / banner off-route di driver screen).
  - Debounce: **30 detik** sekali jeda, **100 m** pergerakan sejak fetch reroute terakhir (konstanta `*_reroute*`).
  - Fetch rute baru: **origin = posisi sekarang**, **dest = tujuan rute kerja**.
  - Jika ada daftar alternatif, entri di indeks terpilih **diganti** dengan hasil Directions baru (bukan menghapus seluruh daftar).

### 2.2 Implikasi untuk sopir

- Pilihan manual “rute 1” adalah **default**, bukan **kunci permanen**; di lapangan, sistem dapat **mengikuti jalur alternatif** yang paling dekat dengan GPS (selama masuk dalam toleransi + jeda waktu).
- Jika kebijakan produk ingin **“jangan pernah ganti otomatis”**, perlu perubahan UX/kode (mis. tombol konfirmasi atau mematikan auto-switch).

### 2.3 Mode aktif, **bukan** sedang navigasi jemput/antar order: gang, pedesan, keluar garis biru

Ini menjawab: *driver sudah “Mulai kerja” / rute aktif, tapi **tidak** sedang mode arahkan ke penumpang* — lalu lewat gang sempit, pedesaan, jalan yang tidak ada di garis biru.*

1. **Kapan dianggap “keluar rute” (banner kuning)?**  
   GPS diproyeksikan ke polyline biru dengan `projectPointOntoPolyline` — jika jarak tegak terdekat **> 350 m** ke segmen mana pun (`targetSeg < 0`), banner **“Anda keluar dari rute. Ikuti garis untuk kembali.”** tampil (`_isOffRoute`). Titik biru tetap mengikuti **GPS** (bukan dipaksa ke tengah jalan utama).

2. **Apa yang dilakukan app (arahkan menyesuaikan jalan)?**  
   - **Tanpa** `_navigatingToOrderId` (tidak sedang navigasi ke penumpang/tujuan order) **dan** ada `_routeDestLatLng` → dipanggil **`_maybeRerouteFromCurrentPosition`**: setelah **debounce** (min. **30 detik** sejak re-route terakhir **dan** **100 m** pergerakan), app meminta **Directions** lagi dari **posisi sekarang** ke **tujuan rute kerja**. Polyline biru **diganti** dengan hasil baru; SnackBar: *“Rute diperbarui untuk kembali ke tujuan.”*  
   - Jadi: **ya**, sistem **mengarahkan ulang** dari lokasi terkini — bukan memaksa kembali ke potongan jalan lama.

3. **Batasan (gang tidak ada di Google Maps)**  
   Jika gang/pedesan **tidak** ada di data jalan Google, garis biru besar kemungkinan tetap lewat jalan utama; saat kamu memotong lewat gang, GPS sering **> 350 m** dari polyline → banner off-route + setelah debounce, re-route dari posisi gang **bisa** memberi rute keluar ke jalan yang dikenali Google — **bukan** selalu persis jalur fisik gang. Itu batasan **Directions API**, bukan bug Traka semata.

4. **UI (implementasi)**  
   - Banner menampilkan **judul + subjudul** (l10n: `driverOffRouteBannerTitle` / `driverOffRouteBannerSubtitle`).  
   - Tombol **“Perbarui rute dari sini”** memanggil `_maybeRerouteFromCurrentPosition(..., force: true)` — **tanpa** debounce 30 s / 100 m; hanya saat **bukan** navigasi jemput order (`_navigatingToOrderId == null`) dan ada `_routeDestLatLng`.  
5. **Saran lanjutan**  
   - **Parameter:** naikkan **350 m** snap (mis. 500–600 m) hanya jika lapangan sering false alarm off-route di area sempit — trade-off: snap ke garis kurang ketat.  
   - **Navigasi ke penumpang** saat off-route: tetap refetch otomatis saat bergerak; tombol manual di banner ini **khusus rute kerja utama** (bisa ditambah aksi serupa untuk mode arahkan jika dibutuhkan).

---

## 3. Parameter operasional (saran penyesuaian)

Nilai ini ada di kode; **sesuaikan setelah uji lapangan** (jalan kabupaten, sinyal, GPS).

| Parameter | Nilai saat ini (kode) | Catatan |
|-----------|------------------------|--------|
| Toleransi “rute terdekat” (auto-switch) | **500 m** (`_autoSwitchNearestRouteToleranceMeters` → `findNearestRouteIndex` di `_checkAndAutoSwitchRoute`) | Hanya jalur yang jarak tegak GPS ke polyline-nya ≤ 500 m dianggap kandidat; di antara kandidat dipilih yang **paling dekat**. Jika semua > 500 m → tidak auto-switch (tunggu re-route off-route atau kembali ke koridor). |
| Jeda antar switch | **10 menit** (`_autoSwitchRouteCooldown`) | Menahan flip-flop; turunkan hanya jika lapangan stabil dan QA setuju. |
| Debounce re-route | **30 s**, **100 m** | Mengurangi spam Directions. |
| Snap “masih di rute” vs off-route (driver) | **350 m** (`projectPointOntoPolyline` → `maxDistanceMeters` di `_getCurrentLocation`) | Lebih jauh dari ini → `targetSeg < 0` → banner off-route; lalu alur re-route (§2.3). |
| Toleransi “titik di dekat polyline” (penumpang) | `RouteUtils.defaultToleranceMeters` = **10 km** | Dipakai `isPointNearAnyRoute` untuk pickup/dropoff penumpang; **bukan** jarak driver–pickup saja. |

---

## 4. Penumpang — mencari driver aktif

### 4.1 `GET /api/match/drivers` (Redis)

- File: `traka-api/src/routes/match.js`.
- Cari driver **geo** dari `lat`/`lng` penumpang (pickup), radius (km), `city`.
- Filter: status **`siap_kerja`**, ada **origin/dest** rute, opsional **kapasitas** (`minCapacity`).
- Jika **`destLat`/`destLng`** valid: urutkan dengan **`matchScore`** (jarak, **selisih bearing** ke ujung rute driver vs ke tujuan penumpang, kapasitas, kebaruan `lastUpdated`).

### 4.2 Peta “Cari travel” — `ActiveDriversService.getActiveDriversForMap`

- File: `lib/services/active_drivers_service.dart`.
- Untuk tiap driver: ambil **alternatif Directions** lagi (**asal→tujuan driver**), tidak memakai indeks rute di HP sebagai filter tunggal.
- **Pickup** dan **dropoff** penumpang harus **dekat salah satu** polyline alternatif itu (“cross-route”), urutan pickup sebelum dropoff, lalu filter posisi driver (belum melewati pickup / pengecualian jarak ±5 km, dll.).
- **Urutan tampilan:** jarak ke titik penjemputan (setelah filter).
- **Batas jarak:** driver ke pickup **≤ 40 km** (`maxDriverDistanceFromPickupMeters`).

Jadi: **penumpang tetap bisa match** selama O/D mereka masuk akal terhadap **salah satu** jalur alternatif Google untuk rute driver, **tanpa** harus sama dengan rute yang sedang dipilih di layar driver.

---

## 5. Tautan ke kode & QA

| Area | Lokasi |
|------|--------|
| Auto-switch & re-route driver | `lib/screens/driver_screen.dart` — `_autoSwitchNearestRouteToleranceMeters`, `_autoSwitchRouteCooldown`, `_checkAndAutoSwitchRoute`, `_maybeRerouteFromCurrentPosition` |
| Polyline / jarak ke rute | `lib/services/route_utils.dart` — `findNearestRouteIndex`, `distanceToPolyline`, `defaultToleranceMeters` |
| Match API | `traka-api/src/routes/match.js` |
| Filter peta penumpang | `lib/services/active_drivers_service.dart` — `getActiveDriversForMap`, `getActiveDriverRoutes` |

- Uji regresi peta & alur: [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md) (bagian Driver & Peta).

---

*Dokumen ini menjelaskan perilaku implementasi; jika ada perubahan konstanta atau UX, perbarui tabel §3 dan tanggal di commit.*
