# Langkah Mengaktifkan Kembali App Check

App Check saat ini **dinonaktifkan** agar login berjalan. Setelah semua berjalan normal, ikuti langkah ini untuk mengaktifkan kembali.

---

## Prasyarat: Android App Harus Terdaftar di App Check

**Penting:** Sebelum debug token bisa dipakai, app Android **harus sudah didaftarkan** di App Check dengan Play Integrity:

1. Firebase Console → **App Check** → **Apps**
2. Cari app Android `id.traka.app`
3. Jika belum ada → **Register** → pilih Play Integrity → tambah SHA-256
4. Jika sudah ada → pastikan status "Registered"

Tanpa ini, debug token tidak akan divalidasi.

---

## Tahap 1: Debug Build (Development)

Untuk testing dengan `flutter run` (debug build):

### 1.1 Dapatkan Debug Token

1. Pastikan `ENFORCE_APP_CHECK = false` di `functions/index.js` (agar login jalan dulu)
2. Aktifkan App Check di app: Firestore `app_config/settings` → set `appCheckEnabled` = `true` (via traka-admin atau manual)
3. Jalankan app: `flutter run` (dengan HP/emulator terhubung via USB)
4. **Ambil debug token dari log HP:**
   - **Apa itu?** `adb logcat` = perintah untuk melihat log yang dicetak oleh app di HP/emulator. Kita filter hanya baris yang berisi "DebugAppCheckProvider" karena token muncul di sana.
   - **Windows:** Buka terminal/PowerShell baru (jangan tutup yang menjalankan `flutter run`), ketik:
     ```bash
     adb logcat | findstr "DebugAppCheckProvider"
     ```
   - **Mac/Linux:** Ganti `findstr` dengan `grep`:
     ```bash
     adb logcat | grep DebugAppCheckProvider
     ```
   - **Jika `adb` tidak dikenali:** Gunakan path lengkap (ganti `[nama]` dengan nama user Windows):
     ```bash
     %LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe logcat | findstr "DebugAppCheckProvider"
     ```
     Atau di PowerShell:
     ```powershell
     & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" logcat | findstr "DebugAppCheckProvider"
     ```
   - **Alternatif (Android Studio):** Buka Android Studio → View → Tool Windows → Logcat. Di kolom filter, ketik `DebugAppCheckProvider`. Jalankan app, coba login, token akan muncul di Logcat.
5. Di terminal lain (atau di HP), lakukan aksi yang memicu App Check (mis. coba login di app)
6. Di logcat akan muncul baris seperti:
   ```
   D DebugAppCheckProvider: Enter this debug secret into the allow list...: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ```
7. **Salin** token (format UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)

### 1.2 Daftarkan Debug Token di Firebase

1. Buka [Firebase Console](https://console.firebase.google.com/) → project **syafiul-traka**
2. Menu kiri: **App Check**
3. Klik **Manage debug tokens** (atau **Debug tokens**)
4. Klik **Add debug token**
5. Tempel token dari langkah 1.1
6. Beri nama (mis. "Device development")
7. Klik **Save**

### 1.3 Uji Login

1. Tutup app, jalankan lagi: `flutter run`
2. Coba login — harus berhasil

---

## Tahap 2: Release Build (Production)

Untuk APK/AAB yang di-upload ke Play Store:

### 2.1 Aktifkan Play Integrity API

1. Buka [Google Cloud Console](https://console.cloud.google.com/)
2. Pilih project **syafiul-traka**
3. **APIs & Services** → **Library**
4. Cari **Google Play Integrity API**
5. Klik **Enable**

### 2.2 Tambah SHA-256 di App Check

1. Ambil SHA-256 dari keystore release:
   ```bash
   keytool -list -v -keystore traka/android/upload-keystore.jks -alias upload
   ```
2. Salin nilai **SHA-256** (format: AA:BB:CC:...)
3. Firebase Console → **App Check** → pilih app Android `id.traka.app`
4. Klik **Play Integrity** → **Edit**
5. Tambah SHA-256 ke **Debug signing certificate** (untuk testing) atau **Release signing certificate**
6. Simpan

### 2.3 Uji di HP Asli

- Play Integrity **hanya berjalan** di device yang punya Google Play Services
- Uji di HP fisik (bukan emulator)
- App harus ter-install dari Play Store atau internal testing untuk Play Integrity penuh

---

## Tahap 3: Aktifkan Enforcement di Cloud Functions

### 3.1 Ubah Kode

Edit `traka/functions/index.js`:

```javascript
// Ubah dari false ke true
const ENFORCE_APP_CHECK = true;
```

### 3.2 Deploy

```bash
cd traka/functions
firebase deploy --only functions
```

### 3.3 Verifikasi

1. Coba login di app (debug atau release)
2. Jika berhasil → App Check aktif
3. Jika error `unauthenticated` → cek debug token (debug) atau SHA-256 + Play Integrity (release)

---

## Checklist Singkat

| Langkah | Debug Build | Release Build |
|---------|-------------|---------------|
| 1. Dapatkan debug token | ✅ Wajib | ❌ Skip |
| 2. Daftarkan di Firebase App Check | ✅ Wajib | ❌ Skip |
| 3. Enable Play Integrity API | ❌ Opsional | ✅ Wajib |
| 4. Tambah SHA-256 di App Check | ❌ Opsional | ✅ Wajib |
| 5. ENFORCE_APP_CHECK = true | ✅ | ✅ |
| 6. firebase deploy --only functions | ✅ | ✅ |

---

## Troubleshooting

| Error | Penyebab | Solusi |
|-------|----------|--------|
| `unauthenticated` saat login | Token App Check invalid | Daftarkan debug token (debug) atau cek SHA-256 (release) |
| Debug token tidak muncul di log | App Check belum init | Cek `app_config/settings.appCheckEnabled` = true di Firestore |
| Play Integrity gagal | API belum enable / SHA salah | Enable Play Integrity API, tambah SHA-256 |
