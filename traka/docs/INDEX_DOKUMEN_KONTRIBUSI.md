# Indeks Dokumen Terkait Kontribusi

Daftar file `.md` yang membahas kontribusi driver dan hubungannya.

---

## File Utama

| File | Isi | Status |
|------|-----|--------|
| **UPDATE_HARGA_GOOGLE_BILLING.md** | Tabel produk Play Console, ID, harga. Sinkron tampilan Kontribusi Aplikasi. | ✅ Terkini |
| **KONTRIBUSI_TRAVEL_CONFIG.md** | Rumus travel: totalPenumpang × (jarak × tarif, min Rp 5.000). Config Firestore. | ✅ Terkini |
| **CEK_KONTRIBUSI_DAN_PEMBAYARAN.md** | Alur pembayaran, trigger, notifikasi. | ⚠️ Perlu update ke model per rute |
| **NOTIFIKASI_BAYAR_KONTRIBUSI_PELANGGARAN.md** | Kapan FCM "Bayar kontribusi" dikirim. | ⚠️ Perlu update ke model per rute |

---

## File Pendukung

| File | Isi |
|------|-----|
| **RANCANGAN_KONTRIBUSI_OPTIMAL.md** | Rancangan terbaru: per penumpang, tier 3, produk 5k–50k, seimbang platform & driver. |
| **RANCANGAN_KONTRIBUSI_GABUNGAN_DRIVER.md** | Rancangan awal (1× kapasitas). Sudah diganti model per rute. |
| **TARIF_KONTRIBUSI_BARANG.md** | Kontribusi kirim barang (jarak × tarif, dokumen/kargo). |
| **KONTRIBUSI_PEMBEBASAN_DRIVER.md** | Pembebasan driver penguji dari kontribusi. |
| **INDEX_CONTRIBUTION_PAYMENTS.md** | Index Firestore untuk `contribution_payments`. |
| **ANALISIS_PROFITABILITAS_HARGA.md** | Analisis tarif, saran UI "Kontribusi Aplikasi". |
| **SARAN_KONTRIBUSI_SAMPAI_PROGRAM_TERAKHIR.md** | Saran perbaikan dan pengembangan kontribusi sampai program terakhir. |
| **KETENTUAN_GOOGLE_PLAY_BILLING.md** | Ketentuan Google Play Billing, acknowledge, verifikasi server. Kesesuaian Traka. |
| **CHECKLIST_PENGATURAN_MANUAL_BILLING.md** | Checklist pengaturan manual Firebase & Google Play agar billing berjalan. |
| **PANDUAN_SEDERHANA_SETUP_BILLING.md** | Penjelasan sederhana untuk pemula: setup pembayaran step-by-step. |
| **CARA_SET_GOOGLE_PLAY_SERVICE_ACCOUNT_KEY.md** | Langkah detail: cara set env var GOOGLE_PLAY_SERVICE_ACCOUNT_KEY di Firebase. |
| **CHECKLIST_SEMUA_PENGATURAN.md** | Checklist lengkap: env vars, Firestore, Play Console, Firebase. |
| **LANGKAH_DAFTAR_GOOGLE_BILLING.md** | Panduan buat produk di Play Console. |
| **JARAK_KAPAL_LAUT.md** | Pengurangan jarak ferry dari kontribusi. |

---

## Model Saat Ini (Per Rute)

- **Trigger:** Selesai rute (driver klik "Berhenti Kerja") → `route_sessions` disimpan dengan `contributionRupiah`
- **Sumber kewajiban travel:** `route_sessions` (contributionPaidAt = null, contributionRupiah > 0)
- **Sumber barang:** `users.totalBarangContributionRupiah` − `contributionBarangPaidUpToRupiah`
- **Notifikasi:** `onRouteSessionCreated` (rute baru), `onUserPaymentDuesUpdate` (barang/pelanggaran)
- **Produk:** `traka_driver_dues_7500` s/d `traka_driver_dues_50000` (sesuai UPDATE_HARGA_GOOGLE_BILLING.md)

---

## Perhitungan Kontribusi Travel (Tampilan)

- **Rumus:** totalPenumpang × (jarak × tarif per km, min Rp 5.000)
- **Tampilan:** Detail Rute, Data Order → "Kontribusi Aplikasi: Rp X"
- **Fallback order lama:** Jika koordinat null tapi tripDistanceKm & totalPenumpang ada → totalPenumpang × minRp (Rp 5.000)
- **Pembayaran:** Produk terdekat (bulat ke atas) dari total kewajiban

### Sinkronisasi

| Lokasi | Implementasi |
|--------|--------------|
| OrderService.getTripTravelContributionForDisplay | Hitung dari jarak; fallback minRp jika koordinat null |
| riwayat_rute_detail_screen | FutureBuilder → tampil Rp X |
| data_order_driver_screen | FutureBuilder → tampil Rp X |
| UPDATE_HARGA_GOOGLE_BILLING.md | Daftar produk Rp 7.500–50.000 |
