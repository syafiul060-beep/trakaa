# Tahap 2: Cloud Functions untuk Phone Auth (Gojek/Grab Style)

Persiapan Cloud Functions agar flow **Phone + OTP** bisa dipakai sebagai metode utama daftar dan login.

---

## Ringkasan Perubahan

| Fungsi | Aksi | Alasan |
|--------|------|--------|
| `requestVerificationCode` | Deprecate | Verifikasi daftar pakai Firebase Phone Auth, bukan email |
| `verifyRegistrationCode` | Deprecate | Sama |
| `sendVerificationCode` | Deprecate | Trigger untuk kirim kode email (tidak dipakai) |
| `requestForgotPasswordCode` | Deprecate | Phone Auth tidak pakai password |
| `verifyForgotPasswordOtpAndGetToken` | Deprecate | Sama |
| `requestLoginVerificationCode` | Deprecate | Login via Phone OTP, device terverifikasi tiap login |
| `verifyLoginVerificationCode` | Deprecate | Sama |
| `checkPhoneExists` | **Tetap dipakai** | Cek nomor terdaftar (untuk UX: "Login" vs "Daftar") |
| `checkEmailExists` | Tetap (opsional) | Untuk user yang nanti tambah email di profil |
| `checkRegistrationAllowed` | Tetap | Cek device/role tetap diperlukan |

---

## Yang Tidak Diubah

- `checkPhoneExists` — sudah siap, format E.164 didukung
- `checkRegistrationAllowed` — device check tetap dipakai
- `checkLoginRateLimit`, `recordLoginFailed`, `recordLoginSuccess` — rate limit tetap
- Semua fungsi lain (orders, FCM, payment, dll.)

---

## Alur Baru (setelah Tahap 3–4)

### Daftar
1. User input nomor → Firebase `verifyPhoneNumber` → OTP SMS
2. User input OTP → `signInWithCredential(PhoneAuthCredential)`
3. Firebase Auth buat user baru (jika belum ada)
4. App cek `users/{uid}` — jika kosong → form lengkapi profil (nama, role)
5. App tulis ke Firestore `users/{uid}` (phoneNumber, displayName, role, dll.)

### Login
1. User input nomor → Firebase `verifyPhoneNumber` → OTP SMS
2. User input OTP → `signInWithCredential(PhoneAuthCredential)`
3. App cek `users/{uid}` — jika ada → lanjut ke main screen

### Lupa sandi
- Tidak relevan (Phone Auth tanpa password)

---

## Status Tahap 2

- [x] Dokumen TAHAP_2 dibuat
- [x] Deprecation comment ditambah ke fungsi email-based
- [ ] Deploy Cloud Functions: `firebase deploy --only functions`
- [ ] Lanjut [Tahap 3: Register Screen](TAHAP_3_REGISTER_SCREEN_PHONE_AUTH.md)

---

## Deploy

Setelah perubahan:

```bash
cd d:\Traka\traka\functions
npm install
firebase deploy --only functions
```

> Fungsi yang di-deprecate tetap ada dan tidak error. Aplikasi lama (email) masih jalan sampai Tahap 3–4 selesai.
