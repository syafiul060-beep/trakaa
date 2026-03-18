# Tahap 4: Login Screen – Phone OTP sebagai Default (Selesai)

Login screen telah diubah agar **Phone + OTP** menjadi metode default (ala Gojek/Grab).

---

## Perubahan

### Default metode login

| Sebelum | Sesudah |
|---------|---------|
| Email + Password (default) | **No. Telepon + OTP (default)** |
| Toggle: Email | Toggle: **No. Telepon** (kiri, dipilih default) |

### Urutan toggle

- **Kiri**: Login dengan No. Telepon (default, dipilih saat buka halaman)
- **Kanan**: Login dengan Email (opsional, untuk user lama yang punya email)

### Alur login Phone (tidak berubah)

1. User pilih "Login dengan No. Telepon" (sudah default)
2. User isi no. telepon → klik "Kirim kode SMS"
3. User isi OTP → klik "Masuk"
4. `signInWithCredential` → `_handlePostLogin` → navigasi

### Alur login Email (tetap ada)

- Untuk user lama yang daftar dengan email
- Toggle ke "Login dengan Email" → isi email + password → Masuk

---

## File yang diubah

- `lib/screens/login_screen.dart`:
  - `_loginWithPhone = true` (default)
  - Urutan toggle: No. Telepon di kiri (default)

---

## Status

- [x] Tahap 4 selesai
- [ ] Uji login dengan Phone OTP (default)
- [ ] Uji login dengan Email (toggle)
- [ ] Lanjut [Tahap 5: Profile Screens](TAHAP_5_PROFILE_SCREENS_EMAIL_OPSIONAL.md)
