# Setup Gmail Environment Variables untuk OTP Email

Jika kode OTP ada di Firestore tapi **tidak sampai ke email**, berarti pengiriman email gagal. Penyebab paling sering: **GMAIL_EMAIL** dan **GMAIL_APP_PASSWORD** belum di-set di Cloud Functions.

---

## Langkah 1: Buat Gmail App Password

1. Buka https://myaccount.google.com/security
2. Aktifkan **2-Step Verification** (jika belum)
3. Buka https://myaccount.google.com/apppasswords
4. Pilih app: **Mail** atau **Other** (ketik "Traka")
5. Klik **Generate**
6. **Copy** password 16 karakter (format: xxxx xxxx xxxx xxxx)
7. Simpan – ini yang dipakai sebagai `GMAIL_APP_PASSWORD`

---

## Langkah 2: Set Environment Variables di Google Cloud

1. Buka https://console.cloud.google.com
2. Pilih project **syafiul-traka**
3. Menu kiri: **Cloud Functions**
4. Cari function **requestVerificationCode**
5. Klik nama function → **Edit** (icon pensil)
6. Buka **Runtime, build, connections and security settings**
7. Di **Runtime environment variables**:
   - Klik **Add variable**
   - `GMAIL_EMAIL` = email Gmail pengirim (mis. `traka@gmail.com`)
   - `GMAIL_APP_PASSWORD` = App Password 16 karakter (tanpa spasi)
8. Klik **Deploy**

---

## Langkah 3: Verifikasi

1. Di app, minta kirim OTP lagi (Tambah/Ubah email)
2. Jika berhasil: email masuk ke inbox (atau Spam)
3. Jika gagal: app menampilkan pesan error

---

## Cek Logs

1. Google Cloud Console → **Logging** → **Logs Explorer**
2. Filter: `resource.type="cloud_function"` AND `resource.labels.function_name="requestVerificationCode"`
3. Cari error seperti:
   - `GMAIL_EMAIL atau GMAIL_APP_PASSWORD kosong`
   - `Invalid login`
   - `Authentication failed`

---

## Catatan

- **Jangan** pakai password Gmail biasa – harus App Password
- Setelah ubah env var, function akan auto-redeploy
- Pastikan email pengirim (`GMAIL_EMAIL`) aktif dan bisa login ke Gmail
