# Tahap 8: Testing & Deploy – Phone Auth Migration

Checklist pengujian dan deployment setelah migrasi ke **Phone Auth** (Tahap 1–7).

---

## Ringkasan

| # | Bagian | Status |
|---|--------|--------|
| 8.1 | Testing – Auth & Profil | ☐ |
| 8.2 | Testing – Layanan (Kirim Barang, Oper Driver) | ☐ |
| 8.3 | Deploy Cloud Functions | ☐ |
| 8.4 | Deploy App (Android / iOS) | ☐ |

---

## 8.1 Testing – Auth & Profil

### Register (Phone + OTP)

- [ ] Buka Register screen
- [ ] Isi nama + no. telepon (format: 0812..., 812..., 62812...)
- [ ] Klik "Kirim kode" → OTP SMS diterima
- [ ] Isi OTP 6 digit → klik "Daftar"
- [ ] Berhasil masuk ke main screen
- [ ] Cek Firestore `users/{uid}`: `phoneNumber` terisi, `email` kosong

### Login (Phone OTP – default)

- [ ] Buka Login screen → "Login dengan No. Telepon" terpilih (default)
- [ ] Isi no. telepon → "Kirim kode SMS"
- [ ] Isi OTP → "Masuk"
- [ ] Berhasil masuk

### Login (Email – toggle)

- [ ] Toggle ke "Login dengan Email"
- [ ] Isi email + password (user legacy atau yang sudah tambah email)
- [ ] Berhasil masuk

### Profil – Tambah Email

- [ ] Login dengan Phone Auth (belum punya email)
- [ ] Buka Profil → "No. Telepon & Email"
- [ ] Klik "Tambah Email" → isi email + password baru
- [ ] Berhasil → email tampil di profil
- [ ] Logout → login dengan email + password → berhasil

### Profil – Ubah No. Telepon

- [ ] Profil → "Ubah No. Telepon" (jika ada)
- [ ] OTP SMS → verifikasi → nomor terupdate

### Forgot Password – No. Telepon

- [ ] Login screen → "Login dengan Email" → "Lupa kata sandi?"
- [ ] Pilih **No. Telepon** (opsi pertama)
- [ ] Isi no. telepon → OTP SMS → verifikasi wajah → atur password baru
- [ ] Berhasil → login dengan email + password baru

### Forgot Password – Email

- [ ] Pilih **Email** (opsi kedua)
- [ ] Isi email → OTP email → verifikasi wajah → atur password baru
- [ ] Berhasil

---

## 8.2 Testing – Layanan (Kirim Barang, Oper Driver)

### Kirim Barang – Cari penerima by phone

- [ ] Buka Kirim Barang (dari penumpang_screen atau pesan_screen)
- [ ] Form: label "No. telepon", hint "08123456789"
- [ ] Ketik no. telepon penerima (format: 0812, 812, 62812) → Cari
- [ ] Penerima terdaftar tampil (foto + nama)
- [ ] Klik "Buka kontak HP" → modal kontak dengan **form pencarian** di atas
- [ ] Ketik nama di search → daftar terfilter
- [ ] Pilih kontak → nomor terisi, penerima terpilih
- [ ] Buat order → berhasil

### Oper Driver – Phone only

- [ ] Driver buka Oper Driver (dari order yang sedang aktif)
- [ ] Form: hanya "No. HP driver kedua" (tanpa email)
- [ ] Klik tombol kontak → modal driver contact picker
- [ ] Form pencarian di atas → ketik nama → daftar terfilter
- [ ] Pilih driver kedua → nomor terisi
- [ ] Submit → barcode muncul → driver kedua scan → transfer berhasil

### Driver Transfer (scan barcode)

- [ ] Driver kedua scan barcode dari Oper Driver
- [ ] Tidak ada form password
- [ ] Langsung proses → order pindah ke driver kedua

---

## 8.3 Deploy Cloud Functions

Pastikan Cloud Functions sudah di-deploy (termasuk deprecation di Tahap 2):

```powershell
cd d:\Traka\traka\functions
npm install
firebase deploy --only functions
```

- [ ] Deploy berhasil tanpa error
- [ ] Cek Firebase Console → Functions → semua fungsi aktif
- [ ] `checkPhoneExists` berjalan (untuk cek nomor terdaftar)

---

## 8.4 Deploy App (Android / iOS)

### Android

```powershell
cd d:\Traka\traka
flutter build apk --release
# atau
flutter build appbundle --release
```

- [ ] Build berhasil
- [ ] Uji APK/AAB di device fisik (bukan emulator) – Phone Auth butuh device nyata
- [ ] Upload ke Play Console (jika production)

### iOS (jika dipakai)

```bash
cd d:\Traka\traka
flutter build ios --release
```

- [ ] Xcode: Archive → Upload ke App Store Connect
- [ ] Pastikan APNs dikonfigurasi (Tahap 1.7)

---

## Catatan

- **Nomor uji**: Untuk development tanpa SMS, tambah nomor di Firebase Console → Authentication → Sign-in method → Phone → Phone numbers for testing
- **Play Integrity**: Pastikan SHA-1/SHA-256 sudah ditambah (Tahap 1.3) agar OTP production jalan
- **Legacy user**: User yang daftar dengan email tetap bisa login dengan email + password

---

## Status

- [ ] 8.1 Testing Auth & Profil selesai
- [ ] 8.2 Testing Layanan selesai
- [ ] 8.3 Cloud Functions deployed
- [ ] 8.4 App deployed (Android / iOS)

**Tahap 8 selesai** → migrasi Phone Auth complete.
