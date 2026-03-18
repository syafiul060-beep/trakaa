# Environment Variables untuk Cloud Functions

Setelah perbaikan keamanan, **GMAIL_EMAIL** dan **GMAIL_APP_PASSWORD** tidak lagi di-hardcode. Wajib dikonfigurasi via Environment Variables.

**Kode memakai `process.env.GMAIL_EMAIL` dan `process.env.GMAIL_APP_PASSWORD`** — bukan `functions.config()`.

## Cara Set di Google Cloud Console (Direkomendasikan)

1. Buka [Google Cloud Console](https://console.cloud.google.com) → pilih project Traka
2. **Cloud Functions** → pilih function (mis. `sendVerificationCode`)
3. Klik **Edit** (icon pensil)
4. **Runtime, build, connections and security settings** → **Runtime environment variables**
5. Tambah:
   - `GMAIL_EMAIL` = email Gmail pengirim (contoh: `traka@gmail.com`)
   - `GMAIL_APP_PASSWORD` = App Password (16 karakter dari myaccount.google.com/apppasswords)
6. **Deploy** ulang

## Cara Set di Firebase Console

1. Buka [Firebase Console](https://console.firebase.google.com) → project Traka
2. **Functions** → **Configuration** → **Environment variables**
3. Tambah `GMAIL_EMAIL` dan `GMAIL_APP_PASSWORD`
4. Deploy ulang: `firebase deploy --only functions`

**Penting:** Setelah ubah env var, wajib deploy ulang functions.

## Mendapatkan Gmail App Password

1. Aktifkan 2-Step Verification di akun Google
2. Buka https://myaccount.google.com/apppasswords
3. Buat App Password untuk "Mail" / "Other"
4. Gunakan password 16 karakter yang dihasilkan

## Verifikasi

Setelah deploy, pastikan:

- `requestVerificationCode` bisa kirim email
- `sendVerificationCode` (trigger) bisa kirim email
- `requestForgotPasswordCode` bisa kirim email
- `requestLoginVerificationCode` bisa kirim email

Jika error "GMAIL_EMAIL dan GMAIL_APP_PASSWORD harus dikonfigurasi", cek Environment Variables di Firebase Console.

## OTP Tidak Masuk?

Lihat **[TROUBLESHOOTING_OTP_EMAIL.md](TROUBLESHOOTING_OTP_EMAIL.md)** untuk panduan lengkap.
