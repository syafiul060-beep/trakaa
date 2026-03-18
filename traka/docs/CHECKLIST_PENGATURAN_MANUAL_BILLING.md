# Checklist Pengaturan Manual Firebase & Google Play untuk Billing

Dokumen ini merangkum **pengaturan manual** yang wajib dilakukan agar pembayaran in-app berjalan.

---

## 1. Google Play Console

### 1.1 Akun & Aplikasi
- [ ] Daftar akun Google Play Developer (biaya sekali ~US$ 25)
- [ ] Buat aplikasi Traka dengan package name **`id.traka.app`**
- [ ] Aktifkan **Monetize** → **In-app products** (terima perjanjian billing, lengkapi profil pembayaran)

### 1.2 Produk In-App (Wajib Buat Manual)

| Produk | Product ID | Harga | Tipe |
|--------|------------|-------|------|
| Kontribusi | `traka_driver_dues_5000` | Rp 5.000 | Managed/Consumable |
| | `traka_driver_dues_7500` | Rp 7.500 | |
| | `traka_driver_dues_10000` | Rp 10.000 | |
| | `traka_driver_dues_12500` | Rp 12.500 | |
| | `traka_driver_dues_15000` | Rp 15.000 | |
| | `traka_driver_dues_20000` | Rp 20.000 | |
| | `traka_driver_dues_25000` | Rp 25.000 | |
| | `traka_driver_dues_30000` | Rp 30.000 | |
| | `traka_driver_dues_40000` | Rp 40.000 | |
| | `traka_driver_dues_50000` | Rp 50.000 | |
| Lacak Driver | `traka_lacak_driver_3000` | Rp 3.000 | Consumable |
| Lacak Barang | `traka_lacak_barang_10k` | Rp 10.000 | Consumable |
| | `traka_lacak_barang_15k` | Rp 15.000 | |
| | `traka_lacak_barang_25k` | Rp 25.000 | |
| Pelanggaran | `traka_violation_fee_5k` | Rp 5.000 | Consumable |

**Lokasi:** Play Console → Monetize → In-app products → Create product

**Penting:** Product ID dan ID opsi pembelian harus sesuai. Lihat `docs/UPDATE_HARGA_GOOGLE_BILLING.md`.

### 1.3 License Testing (untuk Uji Coba)
- [ ] Setup → License testing → Tambah email Gmail tester
- [ ] Dengan ini, pembelian tes tidak debit kartu sungguhan

### 1.4 Users and Permissions (untuk Verifikasi Server)
- [ ] Users and permissions → Invite new users
- [ ] Tambah **email service account** (dari Google Cloud) dengan permission **View financial data**
- Tanpa ini, Cloud Function tidak bisa verifikasi purchase token

---

## 2. Google Cloud Console

### 2.1 API
- [ ] Enable **Google Play Android Developer API**
- Lokasi: APIs & Services → Enable APIs

### 2.2 Service Account
- [ ] IAM & Admin → Service Accounts → Create
- [ ] Buat key JSON untuk service account
- [ ] Simpan file JSON (untuk langkah Firebase)

---

## 3. Firebase Console

### 3.1 Project & Aplikasi
- [ ] Project Firebase terhubung ke project Google Cloud yang sama dengan Play Console
- [ ] Tambah aplikasi Android dengan package **`id.traka.app`**
- [ ] Unduh `google-services.json` ke `android/app/`

### 3.2 Cloud Functions – Environment Variables

**Wajib untuk verifikasi pembayaran:**

| Variable | Nilai | Keterangan |
|---------|-------|------------|
| `GOOGLE_PLAY_SERVICE_ACCOUNT_KEY` | JSON string lengkap service account | Opsi 1: paste isi file JSON |
| ATAU `GOOGLE_PLAY_SERVICE_ACCOUNT_PATH` | Path ke file JSON | Opsi 2: untuk emulator/local |

**Lokasi:** Firebase Console → Functions → Environment variables (atau Configuration)

**Tanpa ini:** Semua verifikasi pembayaran akan **gagal** (verified: false).

### 3.3 Environment Variables Lain (Opsional)
- `GMAIL_EMAIL`, `GMAIL_APP_PASSWORD` – untuk kirim email verifikasi (lihat `ENV_VARS_FUNCTIONS.md`)

---

## 4. Ringkasan Alur Setup

```
1. Google Cloud
   └── Enable Google Play Android Developer API
   └── Buat Service Account + key JSON

2. Google Play Console
   └── Buat produk in-app (sesuai tabel)
   └── Users & permissions: invite email service account (View financial data)

3. Firebase Console
   └── Functions → Environment variables
   └── Set GOOGLE_PLAY_SERVICE_ACCOUNT_KEY (isi JSON service account)

4. Deploy Cloud Functions
   └── firebase deploy --only functions
```

---

## 5. Verifikasi

Setelah setup:

1. **Cek Environment Variable:** Firebase Console → Functions → Environment variables → pastikan `GOOGLE_PLAY_SERVICE_ACCOUNT_KEY` ada
2. **Tes pembayaran:** Login sebagai driver → Bayar kontribusi → selesaikan pembelian tes
3. **Cek Firestore:** `users/{uid}` ter-update, `contribution_payments` ada record baru
4. **Cek Functions Log:** Firebase Console → Functions → Logs → cari `verifyContributionPayment` atau error

---

## 6. Referensi

- `SETUP_GOOGLE_PLAY_VERIFICATION.md` – Detail setup service account
- `LANGKAH_DAFTAR_GOOGLE_BILLING.md` – Panduan lengkap daftar & produk
- `UPDATE_HARGA_GOOGLE_BILLING.md` – Tabel produk & ID
