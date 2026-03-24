# Pembuatan order (hybrid) — selaras dengan aplikasi Flutter

Saat ini order baru dibuat dari klien lewat **Firestore** (`orders` + `.add()`). Jika nanti ada **`POST /api/orders`** (atau Cloud Function setara), server **wajib** mengulang aturan yang sama agar hybrid konsisten.

## Aturan duplikat pra-sepakat

| `orderType`     | Blokir jika sudah ada order **sama** `passengerUid` + `driverUid` dengan status … |
|-----------------|-------------------------------------------------------------------------------------|
| `travel`        | `pending_agreement`                                                                 |
| `kirim_barang`  | `pending_agreement` **atau** `pending_receiver`                                   |

Setelah status **`agreed`** atau **`picked_up`**, duplikat **diizinkan** (pengiriman/perjalanan berikutnya).

## Flag bypass (hanya jika user memilih di UI)

Klien mengirim boolean eksplisit (nama disarankan sama dengan Flutter):

- `bypassDuplicatePendingTravel` — user memilih **“Tetap buat pesanan baru”** pada dialog travel.
- `bypassDuplicatePendingKirimBarang` — sama untuk kirim barang.

Tanpa flag ini, server harus menolak create jika aturan duplikat terpenuhi.

## Respons yang disarankan

- **201** + body order (mis. `{ id, ... }`) jika berhasil.
- **409 Conflict** jika duplikat dan bypass tidak dikirim, mis. body:
  - `{ "error": "duplicate_pending_travel" }` atau
  - `{ "error": "duplicate_pending_kirim_barang" }`
- **403** jika `passengerUid` di body tidak sama dengan UID token.

## Referensi klien (Flutter)

`traka/lib/services/order_service.dart` — `createOrder(..., bypassDuplicatePendingTravel, bypassDuplicatePendingKirimBarang)` dan helper `getPassengerPendingTravelWithDriver` / `getPassengerPendingKirimBarangWithDriver`.

## Analytics (opsional server)

Klien mem-fire event Firebase: `passenger_duplicate_pending_dialog` (`order_kind`, `choice`, `surface`). Untuk funnel end-to-end, backend boleh log event paralel saat **409** atau saat create sukses dengan `bypass=true` (tanpa menyimpan PII berlebihan).
