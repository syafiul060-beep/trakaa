# Transisi status order (Firestore + app)

## Status yang dipakai

| Nilai `status` | Keterangan singkat |
|----------------|-------------------|
| `pending_agreement` | Menunggu kesepakatan (travel / kirim barang setelah penerima setuju) |
| `pending_receiver` | Kirim barang: menunggu penerima terima peran |
| `agreed` | Harga / kesepakatan — siap jemput |
| `picked_up` | Dalam perjalanan / barang dengan driver |
| `completed` | Selesai |
| `cancelled` | Batal |

Konstanta Dart: `OrderService.status*` di `lib/services/order_service.dart`.

## Transisi yang diizinkan (peserta, lewat Firestore rules)

Dari **rules** `firestore.rules` — update oleh penumpang/driver/penerima hanya jika `status` berubah sesuai tabel ini (atau tidak berubah):

| Dari | Ke |
|------|-----|
| `pending_agreement` | `agreed`, `cancelled` |
| `pending_receiver` | `pending_agreement`, `cancelled` |
| `agreed` | `pending_agreement`, `picked_up`, `cancelled` |
| `picked_up` | `completed`, `cancelled` |
| `completed` | *(tidak ada — ubah hanya lewat admin SDK / admin role)* |
| `cancelled` | *(tidak ada — ubah hanya lewat admin)* |

**Admin** (`users/{uid}.role == admin`) tidak dibatasi transisi ini pada `orders` — untuk dukungan manual.

**Hybrid API / Cloud Functions** memakai Admin SDK → **bypass rules** (create order via API, dll.).

### Pesanan terjadwal (`scheduleId` + `scheduledDate`)

- **Format** `scheduledDate`: `yyyy-MM-dd` (WIB dipakai saat **gate** jemput; tanggal string ini adalah “tanggal keberangkatan” yang disepakati).
- **Create (rules + app + `traka-api`)** `scheduleId` dan `scheduledDate` harus **keduanya kosong** atau **keduanya terisi**; jika terisi, tanggal harus cocok pola `yyyy-MM-dd`.
- **Jemput:** transisi `agreed` → `picked_up` dan set pertama `driverArrivedAtPickupAt` hanya jika `scheduledDate` kosong **atau** sama dengan tanggal **WIB hari ini** (server rules memakai `request.time` + 7 jam, selaras `ScheduleIdUtil`).
- **Ubah tanggal / jadwal:** peserta (penumpang/penerima) **tidak** boleh mengubah `scheduleId` / `scheduledDate`. **Driver** boleh **pindah jadwal** lewat `OrderService.updateOrderSchedule` — rules mengizinkan jika **keduanya** berubah bersamaan dan format tanggal valid (selaras sheet Pindah Jadwal). **Admin** tetap boleh mengubah apa pun. Alternatif bisnis: **batalkan** lalu **pesan ulang**.

## Pemetaan ke alur app

- **Sepakat:** `pending_agreement` → `agreed` (penumpang setuju setelah driver setuju; `setPassengerAgreed`).
- **Reset sepakat:** `agreed` → `pending_agreement` (`resetAgreementByPassenger`).
- **Penerima kirim barang:** `pending_receiver` → `pending_agreement` (`setReceiverAgreed`); tolak → `cancelled` (`setReceiverRejected`).
- **Batal dua pihak:** ke `cancelled` dari `pending_agreement` atau `agreed` (dan teoretis `picked_up` jika UI mengizinkan kedua flag batal) — `setCancellationFlag`.
- **Jemput:** `agreed` → `picked_up` (scan, auto-konfirm dekat, dll.).
- **Selesai:** `picked_up` → `completed` (scan selesai, auto-complete, penerima scan, dll.).

## Deploy

Setelah mengubah rules:

```bash
firebase deploy --only firestore:rules
```

Uji cepat di staging: alur sepakat → scan jemput → scan selesai; pastikan tidak ada error `permission-denied`.

## Idempotensi (app — jaringan ganda / double tap)

Alur berikut memakai **`runTransaction`** dan/atau respons sukses jika status **sudah** di target, agar tidak menulis ganda ke Firestore dan **tidak menggandakan** `violation_records` / `outstandingViolationFee` saat konfirmasi otomatis:

- `applyDriverScanPassenger` — sudah `picked_up` → sukses (payload barcode dari dokumen jika ada).
- `applyPassengerScanDriverPickup` — sudah `picked_up` → sukses.
- `setPickedUp` — transaksi; sudah `picked_up` → sukses.
- `applyPassengerScanDriver` — sudah `completed` → sukses; commit hanya lewat transaksi.
- `driverConfirmPickupNoScan` — transaksi + jarak; pelanggaran driver **hanya** jika transisi baru ke `picked_up`.
- `passengerConfirmArrivalNoScan` — transaksi; pelanggaran penumpang **hanya** jika transisi baru ke `completed`.
- `completeOrderWhenFarApart` — transaksi; pelanggaran **hanya** jika transisi baru ke `completed`.
- `applyReceiverScanDriver` — sudah `completed` → sukses; commit lewat transaksi.
- `setCompleted` — sudah `completed` → `true`; transaksi untuk `picked_up` → `completed`.

## Idempotensi (app) — P1 lanjutan

Jalur yang menulis **`violation_records`** + **`users.outstandingViolation*`** hanya boleh jalan jika transaksi Firestore **benar-benar** melakukan `update` order pada percobaan yang **berhasil commit**.

- **Bug yang diperbaiki:** callback `runTransaction` bisa dipanggil ulang saat retry. Flag seperti `appliedNewPickup` / `appliedNewComplete` / `appliedFarApartComplete` harus di-**reset ke `false` di awal setiap invokasi callback**, supaya percobaan pertama yang sempat set `true` lalu gagal commit tidak membuat percobaan berikutnya (yang hanya `return` karena order sudah `completed`) tetap menganggap “perlu catat pelanggaran”.
- **Perilaku yang sudah aman:** `applyDriverScanPassenger`, `applyPassengerScanDriverPickup`, `setPickedUp`, `applyPassengerScanDriver` (tanpa violation), `applyReceiverScanDriver`, `setCompleted` — cek status di dalam transaksi; respons sukses idempoten jika sudah `picked_up` / `completed` sesuai alur.

Detail implementasi: `OrderService` — `driverConfirmPickupNoScan`, `passengerConfirmArrivalNoScan`, `completeOrderWhenFarApart`.

## Riwayat

- **2026-03:** Penambahan `validOrderStatusTransition` + `orderParticipantOrderUpdateValid` di `firestore.rules` (hardening P1).
- **2026-03:** Perbaikan idempotensi flag + transaksi (violation ganda saat retry).
- **2026-03:** Idempotensi transaksi + side-effect pelanggaran terkondisi di `OrderService` (P1).
- **2026-03:** Gate jadwal WIB untuk `picked_up` / `driverArrivedAtPickupAt`, integritas `scheduleId`/`scheduledDate`, pindah jadwal driver di `firestore.rules` + `validateNormalized` API (`order_create.js`).
