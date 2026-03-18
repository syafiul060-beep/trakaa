# Panduan Sederhana: Setup Pembayaran In-App

Panduan ini menjelaskan **dengan bahasa sederhana** apa yang perlu diatur agar pembayaran (kontribusi, lacak driver, dll.) bisa berjalan.

---

## Kenapa Perlu Pengaturan Manual?

Aplikasi Traka memakai **Google Play** untuk pembayaran. Agar pembayaran bisa tervalidasi (tidak palsu), server Traka harus "bertanya" ke Google: "Apakah pembelian ini benar?"

Untuk bisa bertanya ke Google, server butuh **izin khusus** (service account). Izin ini harus dibuat dan diatur manual.

---

## 3 Tempat yang Harus Diatur

```
┌─────────────────────┐
│  1. Google Cloud    │  → Buat "kunci" (service account) agar server boleh akses Google Play
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  2. Google Play     │  → Kasih izin ke "kunci" tadi + buat produk (Rp 5.000, Rp 10.000, dll.)
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  3. Firebase        │  → Simpan "kunci" tadi di Cloud Functions
└─────────────────────┘
```

---

## Langkah 1: Google Cloud – Buat "Kunci"

**Tujuan:** Buat file JSON yang berisi "kunci" agar server Traka boleh tanya ke Google Play.

1. Buka **https://console.cloud.google.com**
2. Pilih project yang sama dengan aplikasi Traka
3. Cari **"Google Play Android Developer API"** → klik **Enable** (aktifkan)
4. Buka **IAM & Admin** → **Service Accounts** → **Create Service Account**
   - Nama: misalnya `traka-billing`
   - Klik **Create and Continue** → **Done**
5. Klik service account yang baru dibuat → tab **Keys** → **Add Key** → **Create new key** → pilih **JSON**
6. File JSON akan terunduh. **Simpan file ini** (akan dipakai di langkah 3)

**Yang didapat:** File JSON (berisi private key, client_email, dll.)

---

## Langkah 2: Google Play – Kasih Izin + Buat Produk

### 2a. Kasih Izin ke "Kunci"

1. Buka **https://play.google.com/console**
2. Pilih aplikasi Traka
3. **Users and permissions** (menu kiri) → **Invite new users**
4. Di kolom email, masukkan **email dari file JSON** (field `client_email`, bentuknya seperti `traka-billing@project-id.iam.gserviceaccount.com`)
5. Centang permission: **View financial data**
6. Klik **Invite**

**Tanpa ini:** Server tidak bisa verifikasi pembelian.

### 2b. Buat Produk

1. **Monetize** → **In-app products** → **Create product**
2. Buat produk satu per satu. Contoh untuk Kontribusi Rp 5.000:
   - Product ID: `traka_driver_dues_5000`
   - Price: Rp 5.000
   - Status: Active

3. Ulangi untuk semua nominal: 7.500, 10.000, 12.500, 15.000, 20.000, 25.000, 30.000, 40.000, 50.000

**Daftar lengkap:** Lihat `UPDATE_HARGA_GOOGLE_BILLING.md`

---

## Langkah 3: Firebase – Simpan "Kunci"

1. Buka **https://console.firebase.google.com**
2. Pilih project Traka
3. **Functions** (menu kiri) → **Environment variables** (atau **Configuration**)
4. Klik **Add variable**
5. Name: `GOOGLE_PLAY_SERVICE_ACCOUNT_KEY`
6. Value: **Buka file JSON** dari Langkah 1, **copy seluruh isinya** (dari `{` sampai `}`), paste ke Value
7. Simpan
8. **Deploy ulang Functions:** `firebase deploy --only functions`

**Penting:** Value harus JSON lengkap (satu baris panjang). Jangan ada spasi/enter yang merusak format.

---

## Cek Apakah Sudah Benar

1. Setelah driver bayar kontribusi, cek **Firestore** → collection `contribution_payments` → harus ada dokumen baru
2. Jika tidak ada / error "Pembayaran tidak valid" → cek:
   - Apakah `GOOGLE_PLAY_SERVICE_ACCOUNT_KEY` sudah di-set di Firebase?
   - Apakah email service account sudah di-invite di Play Console dengan **View financial data**?
   - Apakah produk sudah dibuat dan status **Active**?

---

## Ringkasan 1 Kalimat

**Google Cloud** buat kunci → **Play Console** kasih izin ke kunci + buat produk → **Firebase** simpan isi kunci (JSON) di Environment Variables.
