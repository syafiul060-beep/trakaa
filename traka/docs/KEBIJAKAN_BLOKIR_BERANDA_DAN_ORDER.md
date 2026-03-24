# Kebijakan: blokir beranda & jenis order (**poin 4** — keputusan produk)

Dokumen ini mengunci aturan agar **QA**, **support**, dan **kode** selaras. Ubah kebijakan = update dokumen ini + `OrderService` + l10n jika perlu.

## Ringkasan

| Jenis order | Memblokir beranda penumpang (cari driver baru di peta)? |
|-------------|---------------------------------------------------------|
| **Travel** | **Ya**, hanya jika sudah ada kesepakatan harga: `agreed` atau `picked_up`. **`pending_agreement`** (baru kirim chat / belum sepakat) **tidak** memblokir. |
| **Kirim barang** | **Tidak** (penumpang/pengirim tetap bisa membuka peta beranda untuk travel lain). |
| **Selesai / batal** | `completed`, `cancelled` → **tidak** memblokir (travel). |

## List Pesan — hapus chat travel (bukan kirim barang)

Jika penumpang sudah punya travel **`agreed`/`picked_up`** dengan **driver A**, maka chat travel **`pending_agreement`** dengan **driver lain (B, …)** **tidak boleh dihapus** dari daftar Pesan (ikon kunci + tooltip). **Kirim barang** tetap bisa dihapus seperti biasa. Validasi juga di **`OrderService.deleteOrderAndChat`** (query `passengerUid` + `status` — pastikan indeks Firestore jika deploy pertama kali meminta).

### Indeks Firestore (`getTravelAgreedDriverUidsForPassenger`)

Query: `orders` dengan `passengerUid == …` dan `status in [agreed, picked_up]`. Di repo, **`firestore.indexes.json`** sudah punya composite **`passengerUid` + `status` + `updatedAt`** (cukup untuk query ini; tidak perlu indeks terpisah kecuali konsol meminta variasi lain). Deploy: `firebase deploy --only firestore:indexes`.

## Tab Pesan — jadwal (pesan travel terjadwal)

Jika penumpang sudah punya travel **`agreed`/`picked_up`** (bukan kirim barang), **pesan travel baru dari jadwal** (rekomendasi + hasil “Cari rute lain”) **dinonaktifkan**. **Kirim barang (terjadwal)** dari sheet yang sama **tetap diizinkan**.

- Titik masuk tunggal penumpang untuk buka sheet jadwal: `PesanScreen._onPesanJadwal` → `_PesanJadwalSheet` (kartu rekomendasi dan daftar hasil pencarian memanggil metode yang sama).
- Quick action **Pesan nanti** di peta hanya mengalihkan ke tab yang memuat `PesanScreen`; tidak ada jalur pemesanan jadwal lain di luar `pesan_screen.dart`.

## Implementasi kode

- Logika blokir travel: `OrderService.isTravelOrderBlockingPassengerHomeMap` dan `passengerOrdersContainBlockingTravel`.
- Layar: `PenumpangScreen` overlay + tombol ke tab Pesanan; `PesanScreen` sheet jadwal (`hasBlockingTravelOrder`).

## Jika produk ingin mengubah

Contoh: **kirim barang `agreed` juga memblokir beranda** — tambahkan cabang di helper di atas, perbarui teks overlay (bukan hanya “Travel”), dan tambahkan baris di `QA_REGRESI_ALUR_UTAMA.md`.

## Rujukan

- [`ALUR_PENUMPANG_DRIVER_PERBAIKAN.md`](ALUR_PENUMPANG_DRIVER_PERBAIKAN.md)
- [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md)
