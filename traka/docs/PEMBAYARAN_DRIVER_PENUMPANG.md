# Pembayaran penumpang → driver (bukan escrow)

## Peran Traka

- Traka **bukan pemegang uang** dan **tidak memverifikasi** dana masuk ke rekening driver.
- Aplikasi hanya menampilkan **instruksi pembayaran** yang driver simpan (bank / e-wallet / QRIS) dan alur **“sudah transfer”** + **scan barcode** seperti biasa.
- Konfirmasi pembayaran tunai/non-tunai adalah **kesepakatan penumpang–driver**.

## Data

- `driver_payment_methods` (Firestore + mirror Postgres): metode per driver, status `draft` | `pending_review` | `active` | `suspended`.
- **Nama pemilik rekening/e-wallet** harus sama dengan **displayName** profil Firestore; jika beda → `pending_review` sampai admin setujui atau driver samakan nama via admin.
- **normalized_key** unik (selain status `suspended`) agar nomor tidak dipakai driver lain.

## Field order (Firestore)

- `passengerPayMethod`: `cash` | `bank` | `ewallet` | `qris`
- `passengerPayMethodId`: id metode (jika non-tunai)
- `passengerPayDisclaimerAt`: penumpang mengakui ketentuan
- `passengerPayMarkedAt`: penumpang menandai sudah transfer (non-tunai)

## API (hybrid)

- Driver: `GET/POST/PATCH/DELETE /api/driver/payment-methods` (Bearer).
- Penumpang: `GET /api/orders/:orderId/driver-payment-methods` (peserta order).
- Admin: `GET/POST /api/admin/payment-methods/...` (role admin).

## Alur penumpang

1. Pilih tunai → setuju ketentuan → scan barcode.
2. Pilih bank/e-wallet → salin nomor → “Sudah transfer” → scan barcode.
3. Pilih QRIS → lihat/unduh gambar → “Sudah bayar” → scan barcode.

## Kirim barang: pengirim vs penerima

Ada **dua peran** di order `kirim_barang` (bila `receiverUid` diisi dan berbeda dari `passengerUid`):

| Peran | UID di order | Alur bayar ke driver (hybrid) | Scan barcode |
|--------|----------------|-------------------------------|--------------|
| **Pengirim** | `passengerUid` | **Ya** — sama seperti penumpang travel (tunai / bank / e-wallet / QRIS) sebelum scan ke driver | Scan jemput / selesai seperti penumpang |
| **Penerima** | `receiverUid` | **Tidak** — tidak melewati sheet rekening/QRIS; konfirmasi terima barang langsung scan | Hanya scan **terima barang** |

Jika **pengirim dan penerima satu akun** (`passengerUid == receiverUid`), diperlakukan sebagai **pengirim** (tetap ada alur bayar + scan), bukan sebagai penerima murni.

Traka tetap **bukan** perantara dana; instruksi rekening hanya untuk pembayaran **ke driver** yang diatur pengirim.
