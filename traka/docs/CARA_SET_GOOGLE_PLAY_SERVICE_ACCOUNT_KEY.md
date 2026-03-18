# Cara Set GOOGLE_PLAY_SERVICE_ACCOUNT_KEY di Firebase Functions

Panduan langkah demi langkah untuk mengatur environment variable ini.

---

## Yang Dibutuhkan

1. **File JSON** service account dari Google Cloud (dari langkah "Buat Kunci" di PANDUAN_SEDERHANA_SETUP_BILLING.md)
2. Akses ke **Firebase Console** atau **Google Cloud Console**

---

## Cara 1: Via Google Cloud Console (Paling Mudah)

### Langkah 1: Buka Cloud Functions

1. Buka **https://console.cloud.google.com**
2. Pilih **project** yang sama dengan Firebase (misalnya `syafiul-traka`)
3. Di menu kiri, cari **Cloud Run** (Firebase Functions Gen 2 memakai Cloud Run)
   - Atau buka **Cloud Functions** jika project memakai Gen 1

### Langkah 2: Edit Function

1. Klik salah satu function (misalnya `verifyContributionPayment` atau `us-central1-default-verifyContributionPayment`)
2. Klik **Edit** (ikon pensil) di bagian atas
3. Scroll ke **Runtime, build, connections and security settings** → klik untuk expand
4. Di bagian **Runtime environment variables**, klik **Add variable**
5. **Name:** `GOOGLE_PLAY_SERVICE_ACCOUNT_KEY`
6. **Value:** Buka file JSON service account dengan Notepad/editor → **Select All** → **Copy** → **Paste** ke kolom Value
   - Pastikan seluruh JSON ter-copy (dari `{` sampai `}`)
   - Harus satu baris (tidak ada enter di tengah)
7. Klik **Deploy** / **Save**

### Catatan

- Jika ada banyak functions (verifyContributionPayment, verifyPassengerTrackPayment, dll.), **semua** memakai environment variables yang sama dari project. Set sekali saja.
- Untuk Cloud Run: Variables bisa di-set di level **Service** (revision).

---

## Cara 2: Via Firebase Console

1. Buka **https://console.firebase.google.com**
2. Pilih project Traka
3. **Build** → **Functions** (menu kiri)
4. Cari opsi **Environment variables** atau **Configuration**
   - Lokasi bisa berbeda tergantung versi Firebase Console
   - Jika ada: tambah variable `GOOGLE_PLAY_SERVICE_ACCOUNT_KEY` dengan value = isi file JSON

**Catatan:** Beberapa project Firebase memakai Google Cloud Console untuk env vars. Jika tidak ada menu Environment variables di Firebase Console, pakai **Cara 1**.

---

## Cara 3: Via File .env (untuk Development/Emulator)

Jika menjalankan functions **lokal** (emulator):

1. Di folder `functions/`, buat file `.env` (atau `.env.local`)
2. Tambah baris:
   ```
   GOOGLE_PLAY_SERVICE_ACCOUNT_KEY={"type":"service_account","project_id":"...","private_key_id":"...","private_key":"-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n","client_email":"...@....iam.gserviceaccount.com",...}
   ```
3. **Penting:** Seluruh JSON harus dalam **satu baris**. Ganti `\n` di dalam private_key dengan newline asli jika perlu.
4. **Jangan commit** file `.env` ke Git (tambah ke `.gitignore`)

---

## Format Value yang Benar

Value harus **JSON lengkap** dari file service account. Contoh struktur:

```json
{
  "type": "service_account",
  "project_id": "nama-project",
  "private_key_id": "abc123...",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "client_email": "traka-billing@nama-project.iam.gserviceaccount.com",
  "client_id": "123456789",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  ...
}
```

Saat paste ke Environment variable, **boleh tetap multi-line** (dengan enter) atau **diringkas jadi satu baris**. Yang penting valid JSON.

---

## Setelah Di-set

1. **Deploy ulang** functions (jika edit via Console, biasanya auto-deploy)
2. **Tes:** Driver bayar kontribusi → cek apakah verifikasi berhasil
3. **Cek log:** Firebase Console → Functions → Logs. Jika ada error "GOOGLE_PLAY_SERVICE_ACCOUNT not configured", berarti variable belum terbaca.

---

## Troubleshooting

| Masalah | Solusi |
|---------|--------|
| "verified: false" / Pembayaran tidak valid | Pastikan `GOOGLE_PLAY_SERVICE_ACCOUNT_KEY` sudah di-set dan deploy ulang |
| JSON invalid | Copy-paste ulang dari file asli. Pastikan tidak ada karakter aneh. |
| Tidak ada menu Environment variables | Pakai Google Cloud Console (Cara 1) |
| Service account email belum di-invite | Di Play Console → Users and permissions → Invite email dari `client_email` di JSON |
