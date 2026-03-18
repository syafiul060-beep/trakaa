# Tahap 6: Forgot Password – Phone First (Selesai)

Lupa kata sandi disesuaikan untuk flow Phone Auth: **No. Telepon** sebagai opsi utama.

---

## Konteks

- **Phone Auth users** (default): tidak punya password, login pakai OTP
- **Phone Auth + Email** (tambah di profil): punya password untuk login email
- **Legacy Email users**: punya email + password

"Lupa password" hanya muncul saat user memilih **Login dengan Email**. Jadi yang pakai fitur ini adalah user yang punya email (legacy atau yang sudah tambah email).

---

## Perubahan

### Urutan pilihan metode

| Sebelum | Sesudah |
|---------|---------|
| Email (pertama) | **No. Telepon** (pertama) |
| No. Telepon (kedua) | Email (kedua) |

### Deskripsi

- **Sebelum**: "Gunakan email atau no. telepon (jika sudah ditambahkan ke akun)."
- **Sesudah**: "No. telepon (untuk akun Phone Auth) atau email (untuk akun yang punya email). Lalu verifikasi wajah dan atur kata sandi baru."

---

## Alur (tidak berubah)

1. Pilih metode: **No. Telepon** atau Email
2. Kirim OTP (SMS atau email)
3. Verifikasi OTP → sign in
4. Verifikasi wajah
5. Atur kata sandi baru
6. Selesai → kembali ke login

---

## Catatan

- **Cloud Functions** `requestForgotPasswordCode` dan `verifyForgotPasswordOtpAndGetToken` sudah di-deprecate di Tahap 2, tapi masih dipakai untuk flow **Email**
- Flow **Phone** memakai Firebase `verifyPhoneNumber` dan `signInWithCredential` (tanpa Cloud Function)
- Untuk user Phone Auth yang tambah email: pilih **No. Telepon** → OTP SMS → verifikasi wajah → atur password baru

---

## File yang diubah

- `lib/screens/forgot_password_screen.dart` – urutan pilihan dan teks deskripsi

---

## Status

- [x] Tahap 6 selesai
- [ ] Uji flow lupa password via No. Telepon
- [ ] Uji flow lupa password via Email (legacy)
- [ ] Lanjut [Tahap 7: Layanan & Integrasi](TAHAP_7_LAYANAN_DAN_INTEGRASI.md)
