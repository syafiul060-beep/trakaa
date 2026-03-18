# Perilaku Session & Device – Traka

Dokumentasi untuk pengembang dan tim support tentang cara aplikasi Traka menangani session login dan device.

---

## 0. Spesifikasi Login & Pendaftaran Terpadu

> **Status**: Implementasi selesai.

### Prinsip
- **Pendaftaran**: Hanya nomor HP + password. Email ditambah nanti di Profil.
- **Login**: Nomor HP **atau** email (jika sudah ditambah) + password (sama).
- **Device baru**: OTP saja jika belum ada wajah; OTP + wajah jika sudah ada.

### Pendaftaran

| Input | Verifikasi saat daftar |
|-------|------------------------|
| Nama, nomor HP, password | OTP ke nomor HP |

- Email bisa ditambah nanti di Profil setelah login.

### Login

| Kondisi | Verifikasi |
|---------|------------|
| **Device sama** | Password saja |
| **Device baru, belum ada wajah** | OTP ke nomor HP saja |
| **Device baru, sudah ada wajah** | OTP + verifikasi wajah |

- Login bisa pakai **nomor HP** atau **email** (jika sudah ditambah di Profil) + password yang sama.

### Manfaat
- Pendaftaran sederhana: hanya HP.
- Device sama: cukup password.
- Device baru tanpa wajah: OTP saja.
- Email opsional, bisa ditambah di Profil untuk login alternatif.

### Ubah No. Telepon / Email di Profil (saat sudah login)
- **Ubah No. Telepon**: Verifikasi OTP ke nomor baru via SMS (Firebase Phone Auth).
- **Tambah Email**: Verifikasi OTP ke email baru via email (kode 6 digit), lalu simpan password.
- **Ubah Email**: Verifikasi OTP ke email baru via email (kode 6 digit), lalu simpan.

### Login Setelah Ganti Email (HP sama)
- Setelah ganti email, user mungkin keluar sesi (authStateChanges). Saat login lagi dengan **nomor HP + password**, sistem mengenali akun sudah punya email dan mengizinkan login password (tanpa OTP).
- Jika muncul "Perangkat diblokir karena aktivitas tidak biasa": bisa dari Firebase (terlalu banyak permintaan OTP) atau rate limit Traka (terlalu banyak login gagal). Tunggu beberapa jam lalu coba lagi.

---

## 1. Session Login (HP yang Sama)

### Perilaku
- **Firebase Auth** menyimpan session secara lokal di perangkat (SharedPreferences Android, UserDefaults iOS).
- Pengguna **tidak perlu login berulang** selama:
  - Belum menekan tombol **Keluar** (logout)
  - Masih menggunakan **HP yang sama**
  - Token belum kadaluarsa atau invalid

### Alur Cold Start
1. App dibuka → Splash 600ms
2. Cek `FirebaseAuth.instance.currentUser`
3. Jika `null` → LoginScreen
4. Jika ada user → Cek izin lokasi + device ID
5. Jika izin ditolak → **PermissionRequiredScreen** (Tahap 1 perbaikan)
6. Jika izin OK → Cek Firestore (user doc, suspended, device conflict, device changed)
7. Jika semua OK → Home (PenumpangScreen / DriverScreen)

---

## 2. Device ID & Keamanan

### Aturan
- **1 device aktif per akun per role**: Satu HP hanya boleh dipakai oleh satu akun penumpang **atau** satu akun driver.
- **`users.deviceId`**: Menyimpan device ID terakhir yang berhasil login.
- **`device_accounts`**: Mapping device → akun untuk mencegah satu HP dipakai banyak akun.

### Saat Logout
- **deviceId tidak dihapus** dari Firestore.
- Berguna untuk verifikasi saat login di device baru.

### Saat Pindah Device (HP Baru)
1. User buka app di HP baru → Firebase Auth kosong → LoginScreen
2. User login (email/password atau phone)
3. `currentDeviceId` (HP baru) ≠ `storedDeviceId` (HP lama) → **wajib verifikasi** (saat ini: wajah saja; rencana baru: OTP/email + wajah)
4. Setelah verifikasi berhasil → `deviceId` di Firestore di-update ke HP baru
5. HP lama: saat app dibuka lagi → `deviceChanged` terdeteksi → signOut → LoginScreen

---

## 3. authStateChanges Listener (Tahap 2)

- Listener dipasang di `main.dart` untuk mendeteksi perubahan auth.
- Jika user berubah dari **login → null** (token invalid, sign-out di tempat lain, dll.):
  - `VoiceCallIncomingService.stop()` dipanggil
  - Navigasi ke LoginScreen

## 3b. Perbaikan Session (Token Refresh)

- **AuthSessionService**: Refresh token dengan retry (3x, delay 2 detik) saat gagal.
- **App resume**: DriverScreen & PenumpangScreen refresh token saat app kembali dari background.
- **Timer 25 menit**: Refresh token berkala (token berlaku ~1 jam).
- **RouteJourneyNumberService**: Retry 3x dengan delay sebelum tampilkan "Sesi tidak valid".
- **Splash exception**: signOut sebelum redirect ke Login agar state konsisten.

---

## 4. PermissionRequiredScreen (Tahap 1)

- Ditampilkan ketika user sudah login tapi **menolak izin lokasi/device ID**.
- Opsi:
  - **Coba Lagi**: Request izin lagi
  - **Buka Pengaturan**: Buka pengaturan aplikasi
  - **Keluar**: Sign out dan ke LoginScreen
- Saat app resume dari pengaturan, izin dicek ulang otomatis.

---

## 5. Ringkasan untuk Tim Support

| Skenario | Perilaku |
|----------|----------|
| HP sama, belum logout | Session tetap, tidak perlu login ulang |
| Pindah HP baru | Harus login lagi + verifikasi (OTP/email + wajah, rencana baru) |
| Izin ditolak | Layar PermissionRequiredScreen dengan opsi jelas |
| Token invalid / sign-out di tempat lain | Otomatis redirect ke LoginScreen |
| 1 HP, 2 akun (penumpang + driver) | Diperbolehkan |
| 1 HP, 2 akun penumpang | Tidak diperbolehkan (device conflict) |
