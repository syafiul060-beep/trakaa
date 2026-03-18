# Tahap 5: Profile Screens – Email Opsional (Tambah Email) (Selesai)

Halaman profil telah disesuaikan: **No. Telepon** sebagai primary, **Email** sebagai opsional dengan opsi "Tambah Email".

---

## Perubahan

### Urutan & label di sheet "No. Telepon & Email"

| Sebelum | Sesudah |
|---------|---------|
| Email (primary) | **No. Telepon** (primary, pertama) |
| No. Telepon (opsional) | **Email** (opsional, kedua) |
| "Ubah Email" | "**Tambah Email**" jika kosong, "Ubah Email" jika sudah ada |
| "Tambah No. Telepon" | Tetap (untuk legacy user yang daftar email) |

### Deskripsi

- **Sebelum**: "Email untuk login. No. telepon divalidasi lewat SMS OTP."
- **Sesudah**: "No. telepon untuk login (OTP). Email opsional untuk notifikasi dan invoice."

### Dialog "Tambah Email"

Untuk user Phone Auth yang belum punya email:

1. User pilih "Tambah Email"
2. Dialog: Email, Password baru, Konfirmasi password
3. `linkWithCredential(EmailAuthProvider.credential(email, password))`
4. Update Firestore `users/{uid}.email`
5. User bisa login dengan email + password atau tetap pakai no. telepon + OTP

---

## File yang diubah

- `lib/screens/profile_driver_screen.dart`
- `lib/screens/profile_penumpang_screen.dart`

---

## Fitur

- **Tambah Email**: link `EmailAuthProvider` + password baru
- **Ubah Email**: `verifyBeforeUpdateEmail` (untuk user yang sudah punya email)
- **Tambah/Ubah No. Telepon**: tetap pakai `_TeleponVerifikasiDialog` (OTP SMS)

---

## Status

- [x] Tahap 5 selesai
- [ ] Uji "Tambah Email" di profil (user Phone Auth)
- [ ] Uji login dengan email + password setelah tambah email
- [ ] Lanjut [Tahap 6: Forgot Password](TAHAP_6_FORGOT_PASSWORD_PHONE_FIRST.md)
