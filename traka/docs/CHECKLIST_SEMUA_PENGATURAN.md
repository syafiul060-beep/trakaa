# Checklist Semua Pengaturan Traka

Selain verifikasi payment, berikut pengaturan lain yang perlu diatur.

---

## 1. Cloud Functions – Environment Variables

Set di **Google Cloud Console** → Edit function → Runtime → Environment variables (sama seperti GOOGLE_PLAY_SERVICE_ACCOUNT_KEY):

| Variable | Wajib? | Keterangan |
|---------|--------|------------|
| `GOOGLE_PLAY_SERVICE_ACCOUNT_KEY` | ✅ Ya | Verifikasi pembayaran (kontribusi, lacak, pelanggaran) |
| `GMAIL_EMAIL` | ✅ Ya | Email untuk kirim kode verifikasi, forgot password, login OTP |
| `GMAIL_APP_PASSWORD` | ✅ Ya | App Password Gmail (bukan password biasa) |

**GMAIL_EMAIL & GMAIL_APP_PASSWORD** dipakai oleh 4 function untuk kirim email OTP:

| Function | Kapan dipakai? | Contoh di app |
|----------|----------------|----------------|
| `requestVerificationCode` | User daftar akun baru | Halaman Daftar → user isi email → minta kode → kirim email berisi kode 6 digit |
| `sendVerificationCode` | Trigger otomatis setelah kode disimpan | Setelah `requestVerificationCode` simpan ke Firestore → function ini kirim email |
| `requestForgotPasswordCode` | User lupa password | Halaman Lupa Password → user isi email → kirim kode reset |
| `requestLoginVerificationCode` | User login pakai email (verifikasi device) | Halaman Login OTP → kirim kode ke email untuk verifikasi |

**Alur singkat:**
- **Registrasi:** App panggil `requestVerificationCode` → simpan kode ke Firestore → `sendVerificationCode` (trigger) kirim email.
- **Lupa password:** App panggil `requestForgotPasswordCode` → langsung kirim email (tanpa trigger).
- **Login OTP:** App panggil `requestLoginVerificationCode` → langsung kirim email.

**Cara dapat Gmail App Password:**
1. Aktifkan 2-Step Verification di akun Google
2. Buka https://myaccount.google.com/apppasswords
3. Buat App Password untuk "Mail"
4. Copy password 16 karakter

---

## 2. Firestore – app_config/settings

Pastikan dokumen `app_config/settings` ada dengan field minimal:

| Field | Contoh | Keterangan |
|-------|--------|------------|
| `minKontribusiTravelRupiah` | 5000 | Min kontribusi travel per penumpang |
| `maxKontribusiTravelPerRuteRupiah` | 30000 | Max kontribusi per rute |
| `tarifKontribusiTravelDalamProvinsiPerKm` | 90 | Rp/km dalam provinsi |
| `tarifKontribusiTravelBedaProvinsiPerKm` | 110 | Rp/km antar provinsi |
| `tarifKontribusiTravelBedaPulauPerKm` | 140 | Rp/km lintas pulau |
| `tarifBarangDalamProvinsiPerKm` | 15 | Kirim barang |
| `tarifBarangBedaProvinsiPerKm` | 35 | |
| `tarifBarangLebihDari1ProvinsiPerKm` | 50 | |
| `lacakDriverFeeRupiah` | 3000 | Biaya lacak driver |
| `violationFeeRupiah` | 5000 | Denda pelanggaran |

**Script update:** `cd traka/functions && node scripts/update-app-config-contribution.js`

---

## 3. Google Play Console

- [ ] Produk in-app dibuat (lihat `UPDATE_HARGA_GOOGLE_BILLING.md`)
- [ ] Service account di-invite dengan **View financial data**
- [ ] License testing (email tester) untuk uji pembayaran

---

## 4. Firebase

- [ ] Firestore rules: `firebase deploy --only firestore`
- [ ] Firestore indexes (jika ada error "index required")
- [ ] Hosting (web admin): `firebase deploy --only hosting`
- [ ] Storage rules: `firebase deploy --only storage`

---

## 5. Web Admin (traka-admin)

- [ ] Deploy: `cd traka-admin && npm run deploy`
- [ ] User admin: set `role: "admin"` di Firestore `users/{uid}`
- [ ] Domain: tambah ke Firebase Auth → Authorized domains

---

## 6. Asset Icon Mobil (Penumpang)

Pastikan file ada di `traka/assets/images/`:
- `car_merah.png` – driver diam
- `car_hijau.png` – driver bergerak

Lihat `docs/ASSET_ICON_MOBIL.md` untuk spesifikasi.

---

## 7. Ringkasan Prioritas

| Prioritas | Item | Dampak jika belum |
|-----------|------|-------------------|
| **Tinggi** | GOOGLE_PLAY_SERVICE_ACCOUNT_KEY | Pembayaran tidak tervalidasi |
| **Tinggi** | GMAIL_EMAIL, GMAIL_APP_PASSWORD | Tidak bisa kirim OTP, registrasi/login gagal |
| **Sedang** | app_config/settings | Tarif default, mungkin salah hitung |
| **Sedang** | Produk Play Console | "Item tidak ditemukan" saat bayar |
| **Sedang** | car_merah.png, car_hijau.png | Icon driver tampil sebagai pin merah |
| **Rendah** | Web admin, Firestore rules | Fitur tertentu tidak jalan |
