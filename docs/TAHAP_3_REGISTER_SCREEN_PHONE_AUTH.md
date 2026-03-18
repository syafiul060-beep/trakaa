# Tahap 3: Register Screen – Phone + OTP (Selesai)

Register screen telah diubah dari **Email + Password** ke **Phone + OTP** (ala Gojek/Grab).

---

## Perubahan

### Form fields (sebelum → sesudah)

| Sebelum | Sesudah |
|---------|---------|
| Nama | Nama |
| Email | **No. Telepon** |
| Kode verifikasi (email) | **Kode OTP (SMS)** – muncul setelah "Kirim kode" |
| Password | *(dihapus)* |
| Konfirmasi password | *(dihapus)* |

### Alur baru

1. User isi **nama** dan **no. telepon**
2. User centang **Terms & Privacy**
3. User klik **Kirim kode** (ikon di field telepon) → Firebase mengirim OTP via SMS
4. User isi **kode OTP** (6 digit)
5. User klik **Daftar** → `signInWithCredential` → simpan ke Firestore → navigasi ke main screen

### Data Firestore `users/{uid}`

- `phoneNumber` (E.164, mis. +628123456789)
- `email` (kosong, bisa ditambah di profil)
- `displayName`, `role`, `region`, `latitude`, `longitude`, dll.

---

## File yang diubah

- `lib/screens/register_screen.dart` – flow Phone + OTP
- `lib/l10n/app_localizations.dart` – tambah `phoneHintRegister`

---

## Fitur yang dipertahankan

- Cek device (`checkRegistrationAllowed`)
- Cek lokasi Indonesia & deteksi Fake GPS
- Cek nomor sudah terdaftar (`checkPhoneExists`) sebelum kirim OTP
- Penanganan akun dalam proses penghapusan
- `recordRegistration`, FCM, VoiceCallIncomingService

---

## Status

- [x] Tahap 3 selesai
- [ ] Uji di HP Android asli
- [ ] Lanjut [Tahap 4: Login Screen](TAHAP_4_LOGIN_SCREEN_PHONE_AUTH.md)
