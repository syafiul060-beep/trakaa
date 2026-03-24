# Barcode penumpang ↔ driver & konfirmasi otomatis

Ringkasan agar **QA**, **support**, dan **kode** selaras. Detail teknis ada di `OrderService`, `data_order_driver_screen.dart`, `data_order_screen.dart`, `scan_barcode_penumpang_screen.dart`.

## Format barcode driver

- **PICKUP** — `TRAKA:orderId:D:PICKUP:uuid` — penumpang/pengirim scan saat dijemput → status `picked_up`, driver dapat barcode COMPLETE.
- **COMPLETE** — `TRAKA:orderId:D:COMPLETE:uuid` — penumpang scan di tujuan (travel) atau penerima scan (kirim barang) → selesai.

## Travel vs kirim barang

| Aspek | Travel | Kirim barang |
|--------|--------|----------------|
| Siapa scan PICKUP | Penumpang | Pengirim (passengerUid) |
| Siapa scan selesai | Penumpang (COMPLETE) | **Penerima** scan COMPLETE (bukan pengirim, jika flow penerima) |
| Auto konfirmasi penjemputan (15 menit / 1 km) | **Ya** (di app driver) | **Tidak** — wajib scan; lihat `_checkAutoConfirmPickup` di `data_order_driver_screen.dart` |
| Denda jika konfirmasi tanpa scan (otomatis) | Driver / penumpang (travel), sesuai `ViolationService` | Tidak membebani denda travel untuk pickup otomatis (pickup otomatis memang tidak jalan) |
| Auto selesai saat menjauh (driver) | Hanya order travel `picked_up` (`getPickedUpTravelOrdersForDriver`) | Tidak ikut auto-complete menjauh |

## Konfirmasi otomatis (tanpa scan barcode)

1. **Penjemputan (travel)** — Driver & penumpang berdekatan (≤30 m): set `driverArrivedAtPickupAt`. Jika **travel** dan (15 menit berdekatan **atau** perpindahan 1 km dari titik pertama berdekatan) → `driverConfirmPickupNoScan` + `autoConfirmPickup` + denda driver (travel) jika tanpa scan.
   - **Lokasi penumpang yang dipakai untuk jarak:** utamakan **`passengerLiveLat`/`Lng`** bila masih segar (≤5 menit setelah `passengerLiveUpdatedAt`) — dipush ~5 detik sekali saat driver sudah ketuk navigasi ke penumpang (`driverNavigatingToPickupAt`). Jika tidak ada live segar, dipakai **`passengerLat`/`Lng`** (termasuk update dari chat penumpang tiap ~30 detik jika bergerak ≥50 m). Ini mengurangi salah jarak saat penumpang berpindah titik jemput.
   - **Operasional:** driver disarankan segera ketuk **Ya, arahkan** setelah kesepakatan agar live jalan; penumpang jangan force-stop app dan pertahankan izin lokasi. UI: tab driver (info oranye) + banner biru di chat penumpang (`pickupOperational*` di `app_localizations.dart`).
2. **Selesai (travel)** — Logika jarak / `passengerConfirmArrivalNoScan` / auto saat menjauh: lihat `OrderService` dan timer di `data_order_driver_screen.dart`.
   - **Update `passengerLat`/`Lng` saat `picked_up`:** penumpang (travel) tetap bisa push cadangan dari chat saat perjalanan (`OrderService.updatePassengerLocation` + timer di `chat_room_penumpang_screen.dart`), agar **auto selesai saat menjauh** memakai titik yang sama dengan urutan live → `passengerLat`/`Lng` (`coordsForDriverPickupProximity` di `completeOrderWhenFarApart` dan `_checkAutoCompleteWhenFarApart`).
3. **Syarat** — `passenger*` violation fee pada `passengerConfirmArrivalNoScan` hanya untuk **travel** (`orderType == travel`).

## Validasi di `OrderService` (konsisten dengan UI)

- **Konfirmasi otomatis penjemputan** (`driverConfirmPickupNoScan`): hanya **travel** — kirim barang harus pakai scan.
- **Konfirmasi tanpa scan di tujuan** (`passengerConfirmArrivalNoScan`) & **tombol “bisa konfirmasi”** (`passengerCanConfirmArrival`): hanya **travel**.
- **Auto selesai saat menjauh** (`completeOrderWhenFarApart`): hanya **travel** (selain filter query di app).

> **Catatan keamanan:** Aturan bisnis dicerminkan di **Firestore Security Rules** untuk `orders` (identitas peserta + `orderType` tidak boleh diubah; kirim barang tidak boleh flag `autoConfirm*`). Detail dan saran Cloud Function: [`FIRESTORE_ORDERS_SECURITY.md`](FIRESTORE_ORDERS_SECURITY.md).

## UI penumpang (Data Order)

- Banner **driver sudah di titik penjemputan**: teks **berbeda** untuk kirim barang (tanpa hitungan 15 menit palsu) vs travel; copy disingkat agar muat di layar kecil.
- Tab Driver (picked up): kotak info oranye dua baris — **travel** (scan/denda/auto menjauh) vs **kirim barang** (scan penerima, tanpa auto menjauh).
- Layar **Scan barcode driver**: dua baris — travel (PICKUP → COMPLETE) vs kirim barang (pengirim / penerima).

## Scan layar

- `ScanBarcodePenumpangScreen`: jika scan COMPLETE gagal sebagai penumpang, dicoba sebagai **penerima** (`applyReceiverScanDriver`) untuk kirim barang.

## Audit server

- Collection `scan_audit_log`: scan barcode **dan** event **`auto_confirm_pickup` / `auto_confirm_complete`** (travel) ditulis oleh Cloud Function `onOrderUpdatedScan`. Lihat [`SCAN_AUDIT_LOG.md`](SCAN_AUDIT_LOG.md).

## Rujukan hukum / produk

- `terms_screen.dart` / kebijakan: scan vs konfirmasi otomatis & denda.
- `KEBIJAKAN_BLOKIR_BERANDA_DAN_ORDER.md` — blokir beranda (travel vs kirim barang).
