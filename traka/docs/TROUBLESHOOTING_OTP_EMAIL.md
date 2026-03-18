# Troubleshooting: OTP Tidak Masuk di Email

Jika kode verifikasi (OTP) tidak sampai ke inbox email, periksa langkah berikut.

**Jika kode ada di Firestore tapi email tidak sampai** → Pengiriman email gagal. Ikuti **[SETUP_GMAIL_ENV_VARS.md](SETUP_GMAIL_ENV_VARS.md)** untuk set `GMAIL_EMAIL` dan `GMAIL_APP_PASSWORD`.

---

## 1. Cek Environment Variables (Paling Sering)

Cloud Function `sendVerificationCode` membutuhkan **GMAIL_EMAIL** dan **GMAIL_APP_PASSWORD**.

### Cara set di Google Cloud Console

1. Buka [Google Cloud Console](https://console.cloud.google.com)
2. Pilih project Firebase Anda (Traka)
3. **Cloud Functions** → pilih salah satu function (mis. `sendVerificationCode` atau `requestVerificationCode`)
4. Klik **Edit** (icon pensil)
5. Di bagian **Runtime, build, connections and security settings** → **Runtime environment variables**
6. Tambah:
   - `GMAIL_EMAIL` = email Gmail pengirim (contoh: `traka@gmail.com`)
   - `GMAIL_APP_PASSWORD` = App Password (bukan password biasa)

7. **Deploy** ulang function

### Alternatif: Firebase Console

1. Buka [Firebase Console](https://console.firebase.google.com) → project Traka
2. **Functions** → **Configuration** (atau **Environment variables**)
3. Tambah `GMAIL_EMAIL` dan `GMAIL_APP_PASSWORD`
4. Deploy ulang: `firebase deploy --only functions`

---

## 2. Gmail App Password (Wajib)

Gmail tidak mengizinkan login dengan password biasa untuk aplikasi. Harus pakai **App Password**.

### Langkah

1. Aktifkan **2-Step Verification** di [Google Account](https://myaccount.google.com/security)
2. Buka [App Passwords](https://myaccount.google.com/apppasswords)
3. Pilih app: **Mail** atau **Other** (ketik "Traka")
4. Copy password 16 karakter yang dihasilkan
5. Gunakan sebagai nilai `GMAIL_APP_PASSWORD` (tanpa spasi)

---

## 3. Cek Log Cloud Functions

Jika env var sudah benar tapi email tetap tidak masuk:

1. **Firebase Console** → **Functions** → **Logs**
2. Atau **Google Cloud Console** → **Logging** → filter `sendVerificationCode`
3. Cari error seperti:
   - `GMAIL_EMAIL dan GMAIL_APP_PASSWORD harus dikonfigurasi`
   - `Invalid login` / `Authentication failed`
   - `Connection timeout`

---

## 4. Cek Folder Spam / Promosi

Email verifikasi bisa masuk ke **Spam** atau **Promosi**. Cek folder tersebut dan tandai "Bukan spam" jika perlu.

---

## 5. Rate Limit

Fungsi `requestVerificationCode` membatasi **3 kirim per email per 15 menit**. Jika melebihi, akan error "Terlalu banyak permintaan". Tunggu 15 menit lalu coba lagi.

---

## 6. Verifikasi Alur

1. App memanggil `requestVerificationCode` dengan email
2. Function menulis ke Firestore `verification_codes/{email}`
3. Function mengirim email langsung via Nodemailer + Gmail SMTP
4. **Jika gagal**, app akan menampilkan pesan error (mis. "Gagal mengirim kode verifikasi ke email" atau "Periksa Gmail App Password")

---

## 7. Test Manual (Opsional)

Untuk memastikan Gmail SMTP berfungsi, bisa test dengan script Node.js lokal:

```bash
cd traka/functions
node -e "
const nodemailer = require('nodemailer');
const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: { user: process.env.GMAIL_EMAIL, pass: process.env.GMAIL_APP_PASSWORD }
});
transporter.sendMail({
  from: process.env.GMAIL_EMAIL,
  to: 'email-tujuan@example.com',
  subject: 'Test',
  text: 'Test OTP'
}).then(() => console.log('OK')).catch(e => console.error(e));
"
```

Jalankan dengan: `GMAIL_EMAIL=xxx@gmail.com GMAIL_APP_PASSWORD=xxxx node -e "..."`

---

## Perubahan Terbaru

Email OTP sekarang dikirim **langsung** di `requestVerificationCode` (bukan via Firestore trigger). Jika konfigurasi salah, **app akan menampilkan pesan error** saat user minta kirim kode. Cek pesan error di app untuk petunjuk.

## Ringkasan Checklist

- [ ] `GMAIL_EMAIL` dan `GMAIL_APP_PASSWORD` sudah di-set di Cloud Functions
- [ ] Menggunakan App Password, bukan password Gmail biasa
- [ ] 2-Step Verification sudah aktif di akun Google
- [ ] Sudah deploy ulang functions setelah ubah env var
- [ ] Cek folder Spam/Promosi di inbox
- [ ] Cek Logs di Firebase/Google Cloud untuk error
