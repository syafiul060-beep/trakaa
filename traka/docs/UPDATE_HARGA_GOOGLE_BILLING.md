# Update Harga di Google Play Billing

Panduan singkat membuat dan mengubah harga produk Traka di Google Play Console.

**Checklist operasional + validasi server (Tahap 1–4):** [BILLING_TAHAP_1_4.md](./BILLING_TAHAP_1_4.md).

---

## 1. Buka Halaman Produk

1. Buka [Google Play Console](https://play.google.com/console)
2. Pilih aplikasi **Traka**
3. Menu kiri: **Monetisasi dengan Google Play** → **Produk** → **Produk sekali beli**
4. Klik **Buat produk sekali beli**

---

## 2. Tabel Produk (Copy-Paste)

**Penting:** Field **ID opsi pembelian** (Langkah 2) hanya menerima **angka, huruf kecil, dan tanda hubung (-)**. Jangan pakai underscore (_).

| Produk | ID Produk (Langkah 1) | ID Opsi Pembelian (Langkah 2) | Harga | Keterangan |
|--------|------------------------|-------------------------------|-------|------------|
| Lacak Driver | `traka_lacak_driver_3000` | `traka-lacak-driver-3000` | Rp 3.000 | Penumpang lacak posisi driver di peta |
| Lacak Barang (dalam provinsi) | `traka_lacak_barang_10k` | `traka-lacak-barang-10k` | Rp 10.000 | Pengirim/penerima lacak barang, sama provinsi |
| Lacak Barang (beda provinsi) | `traka_lacak_barang_15k` | `traka-lacak-barang-15k` | Rp 15.000 | Pengirim/penerima lacak barang, beda provinsi |
| Lacak Barang (>1 provinsi) | `traka_lacak_barang_25k` | `traka-lacak-barang-25k` | Rp 25.000 | Pengirim/penerima lacak barang, >1 provinsi |
| Pelanggaran | `traka_violation_fee_5k` | `traka-violation-fee-5k` | Rp 5.000 | Denda tidak scan barcode (driver/penumpang) |
| Kontribusi | `traka_driver_dues_5000` | `traka-driver-dues-5000` | Rp 5.000 | Trip minimal / kewajiban kecil |
| Kontribusi gabungan | `traka_driver_dues_7500` | `traka-driver-dues-7500` | Rp 7.500 | Total kewajiban ≤ Rp 7.500 |
| | `traka_driver_dues_10000` | `traka-driver-dues-10000` | Rp 10.000 | Total kewajiban ≤ Rp 10.000 |
| | `traka_driver_dues_12500` | `traka-driver-dues-12500` | Rp 12.500 | Total kewajiban ≤ Rp 12.500 |
| | `traka_driver_dues_15000` | `traka-driver-dues-15000` | Rp 15.000 | Total kewajiban ≤ Rp 15.000 |
| | `traka_driver_dues_17500` | `traka-driver-dues-17500` | Rp 17.500 | Total kewajiban ≤ Rp 17.500 |
| | `traka_driver_dues_20000` | `traka-driver-dues-20000` | Rp 20.000 | Total kewajiban ≤ Rp 20.000 |
| | `traka_driver_dues_25000` | `traka-driver-dues-25000` | Rp 25.000 | Total kewajiban ≤ Rp 25.000 |
| | `traka_driver_dues_30000` | `traka-driver-dues-30000` | Rp 30.000 | Total kewajiban ≤ Rp 30.000 |
| | `traka_driver_dues_40000` | `traka-driver-dues-40000` | Rp 40.000 | Total kewajiban ≤ Rp 40.000 |
| | `traka_driver_dues_50000` | `traka-driver-dues-50000` | Rp 50.000 | Total kewajiban ≤ Rp 50.000 |
| | `traka_driver_dues_60000` | `traka-driver-dues-60000` | Rp 60.000 | Total kewajiban ≤ Rp 60.000 |
| | `traka_driver_dues_75000` | `traka-driver-dues-75000` | Rp 75.000 | Total kewajiban ≤ Rp 75.000 |
| | `traka_driver_dues_100000` | `traka-driver-dues-100000` | Rp 100.000 | Total kewajiban ≤ Rp 100.000 |
| | `traka_driver_dues_150000` | `traka-driver-dues-150000` | Rp 150.000 | Total kewajiban ≤ Rp 150.000 |
| | `traka_driver_dues_200000` | `traka-driver-dues-200000` | Rp 200.000 | Total kewajiban ≤ Rp 200.000 |

**Kontribusi gabungan** = travel + kirim barang + pelanggaran. App pilih produk dengan nominal terdekat (bulat ke atas) sesuai total kewajiban driver.

**Driver kontribusi kirim barang:** Saat driver selesai mengantar barang (penerima scan barcode), kontribusi kirim barang dihitung dari jarak × tarif (Admin Settings). Nilai ini ditambah ke `totalBarangContributionRupiah` dan digabung dengan kontribusi travel + pelanggaran. Driver bayar sekali via produk `traka_driver_dues_*` sesuai total.

---

## 3. Langkah Buat Produk (Step by Step)

Ada **2 field ID** yang berbeda — jangan tertukar:

| Langkah | Nama Field | Format | Contoh |
|---------|------------|--------|--------|
| **1** | **ID Produk** | Boleh underscore (_) | `traka_driver_dues_5000` |
| **2** | **ID opsi pembelian** | Hanya huruf kecil, angka, tanda hubung (-). **Tidak boleh underscore** | `traka-driver-dues-5000` |

- **ID Produk** = dipakai di kode app (query Billing API)
- **ID opsi pembelian** = internal Play Console, format berbeda

---

### Langkah 1 – Detail produk

| Field | Isi |
|-------|-----|
| **ID Produk** | Pakai **underscore**. Contoh: `traka_driver_dues_5000` (copy dari kolom "ID Produk" di tabel) |
| **Nama** | Nama singkat (mis. "Kontribusi Rp 5.000") |
| **Deskripsi** | Deskripsi singkat untuk review |
| **Tag** | Kosongkan (opsional) |

Klik **Berikutnya**.

---

### Langkah 2 – Ketersediaan dan harga

#### A. Opsi pembelian (Purchase options)

| Field | Isi |
|-------|-----|
| **ID opsi pembelian** | Pakai **tanda hubung (-)** saja. Ganti semua `_` → `-`. Contoh: `traka-driver-dues-5000` |
| **Jenis pembelian** | Biarkan **Beli** |
| **Tag** | Kosongkan |

**Jika form merah:** Field **ID opsi pembelian** hanya menerima huruf kecil, angka, dan tanda hubung. Ganti underscore dengan tanda hubung.

#### B. Opsi lanjutan (klik untuk buka)

- **Quantities and limits:** Aktifkan untuk Lacak Driver, Lacak Barang, Pelanggaran. Untuk Kontribusi bisa default.

#### C. Pajak, kepatuhan, dan program

- **Kategori pajak:** Penjualan aplikasi digital (default)
- **Rating usia:** Sama dengan aplikasi
- **Pembatasan lokasi:** Default (tidak ada batasan)

#### D. Harga

- Set harga sesuai tabel (mis. Rp 3.000 untuk Lacak Driver)

#### E. Aktifkan

- Klik **Aktifkan** untuk menyimpan dan mengaktifkan produk.

---

## 4. Sinkronisasi dengan Web Admin

Nilai di **Admin** (Firestore `app_config/settings`) harus sesuai dengan produk di Play Console. App memakai nilai Admin untuk memilih Product ID.

| Field di Admin | Nilai default | Produk Play | Catatan |
|----------------|---------------|-------------|---------|
| `lacakDriverFeeRupiah` | 3000 | `traka_lacak_driver_3000` | Jika diubah (mis. 5000), buat produk `traka_lacak_driver_5000` |
| `lacakBarangDalamProvinsiRupiah` | 10000 | `traka_lacak_barang_10k` | Hanya 10k, 15k, 25k yang punya produk. Nilai lain perlu produk baru. |
| `lacakBarangBedaProvinsiRupiah` | 15000 | `traka_lacak_barang_15k` | |
| `lacakBarangLebihDari1ProvinsiRupiah` | 25000 | `traka_lacak_barang_25k` | |
| `violationFeeRupiah` | 5000 | `traka_violation_fee_5k` | Jika diubah (mis. 10000), buat produk `traka_violation_fee_10k` |

**Penting:** Agar produk di app berfungsi, nilai Admin harus sama dengan nominal produk yang ada di Play Console. Jika Admin diubah, buat produk baru di Play Console dengan ID yang sesuai.

---

## 5. Update Harga (Produk Sudah Ada)

1. **Produk sekali beli** → klik produk
2. Buka **Opsi pembelian** → klik **Edit** pada Harga
3. Ubah harga → Simpan

**Catatan:** ID produk tidak bisa diubah setelah dibuat.

---

## 6. Masalah Umum

| Masalah | Solusi |
|---------|--------|
| **Form merah / ID opsi pembelian error** | Field ini hanya menerima angka, huruf kecil, dan **tanda hubung (-)**. Ganti `_` dengan `-`. Contoh: `traka-lacak-driver-3000` |
| **"ID Produk ini telah dihapus"** | ID yang pernah dibuat lalu dihapus **tidak bisa dipakai lagi**. Gunakan ID baru: Kontribusi → `traka_driver_dues_7500`, Lacak Driver → `traka_lacak_driver_3000`, Lacak Barang → `traka_lacak_barang_10k/15k/25k`. |
| "Item tidak dapat ditemukan" | Produk belum dibuat. Buat produk dengan ID persis seperti tabel. |
| Produk tidak muncul di app | Cek status **Aktif**. Pastikan app sudah di-upload ke track testing. |
| Harga di Admin beda dengan Play | Harga di Play Console yang berlaku. Sesuaikan Admin atau buat produk baru. |

---

## 7. Referensi

- Detail lengkap: `docs/LANGKAH_DAFTAR_GOOGLE_BILLING.md`
