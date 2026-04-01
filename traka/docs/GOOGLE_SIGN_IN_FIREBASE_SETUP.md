# Konfigurasi Google Sign-In (Firebase + Android + iOS)

Panduan ini melengkapi alur **Daftar / Masuk dengan Google** di app Flutter `traka/`. Tanpa langkah di bawah, `google_sign_in` sering gagal (misalnya error 10 *DEVELOPER_ERROR* di Android, atau redirect OAuth gagal di iOS).

---

## 1. Firebase Console — aktifkan provider Google

1. Buka [Firebase Console](https://console.firebase.google.com/) → pilih proyek Anda (mis. `syafiul-traka`).
2. **Build** → **Authentication** → tab **Sign-in method**.
3. Klik **Google** → **Enable** → pilih **Project support email** → **Save**.

Ini mendaftarkan Google sebagai penyedia login; tetap perlu client OAuth di setiap platform (langkah berikut).

---

## 2. Android — SHA-1 / SHA-256 + `google-services.json`

**Package / application ID app Traka:** `id.traka.app` (lihat `android/app/build.gradle.kts`).

### 2a. Tambahkan fingerprint ke Firebase

1. Di Firebase: **Project settings** (ikon roda gigi) → tab **Your apps** → pilih app Android Traka (atau **Add app** jika belum ada; isi `id.traka.app`).
2. Buka bagian **SHA certificate fingerprints**.
3. Tambahkan minimal **SHA-1** (wajib untuk Google Sign-In / Play Integrity). **SHA-256** disarankan ikut ditambahkan.

**Debug (untuk uji di emulator / HP dari Android Studio):**

```bash
# Windows (PowerShell) — sesuaikan path user Anda
keytool -list -v -alias androiddebugkey -keystore "$env:USERPROFILE\.android\debug.keystore" -storepass android -keypass android
```

**Release (Play Store / keystore rilis Anda):**

```bash
keytool -list -v -alias <KEY_ALIAS> -keystore <path_ke_upload-keystore.jks>
```

Salin baris **SHA1** dan **SHA256** (format `XX:XX:...`) ke Firebase.

### 2b. Unduh ulang `google-services.json`

1. Masih di **Project settings** → app Android → **Download google-services.json**.
2. Ganti file lokal: **`traka/android/app/google-services.json`**.

### 2c. Pastikan `oauth_client` tidak kosong

Buka JSON yang baru. Di dalam `client` untuk `id.traka.app`, array **`oauth_client`** harus berisi entri (biasanya tipe **android** dan sering juga **web**). Jika masih `[]`, biasanya **SHA-1 belum tersimpan** atau app Android belum dipasangkan benar di Firebase — ulangi 2a–2b.

---

## 3. iOS — `GoogleService-Info.plist` + URL scheme

**Bundle ID Xcode Traka:** `id.traka.app` (bukan placeholder `com.example`).

### 3a. App iOS di Firebase

1. **Project settings** → **Your apps** → **Add app** → iOS → Bundle ID **`id.traka.app`**.
2. Unduh **`GoogleService-Info.plist`** → taruh di **`traka/ios/Runner/`** (ganti file lama jika perlu).

### 3b. Isi wajib di plist

Pastikan file berisi paling tidak:

- `CLIENT_ID`
- `REVERSED_CLIENT_ID` (dipakai sebagai **URL scheme**)
- `BUNDLE_ID` = `id.traka.app`

Jika **tidak ada** `REVERSED_CLIENT_ID`, plist belum lengkap atau app iOS salah terdaftar di Firebase.

### 3c. `Info.plist` — URL scheme Google

Di **`traka/ios/Runner/Info.plist`**, tambahkan (atau gabungkan dengan `CFBundleURLTypes` yang sudah ada) **satu** entri yang memakai nilai **persis** dari `REVERSED_CLIENT_ID`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>PASTE_REVERSED_CLIENT_ID_DI_SINI</string>
    </array>
  </dict>
</array>
```

Ganti `PASTE_REVERSED_CLIENT_ID_DI_SINI` dengan string dari baris `REVERSED_CLIENT_ID` di `GoogleService-Info.plist` (contoh bentuk: `com.googleusercontent.apps.1234567890-abcdef`).

Referensi resmi: [Google Sign-In for iOS — start integrating](https://developers.google.com/identity/sign-in/ios/start-integrating).

### 3d. Xcode

- Buka **`ios/Runner.xcworkspace`** → target **Runner** → **Signing & Capabilities**: team & bundle ID konsisten dengan yang di Firebase.

---

## 4. Setelah mengganti file konfigurasi

```bash
cd traka
flutter clean
flutter pub get
```

Lalu build/run di **perangkat / emulator asli** (Google Play services diperlukan untuk Android).

---

## 5. Troubleshooting singkat

| Gejala | Periksa |
|--------|---------|
| Android `ApiException: 10` / DEVELOPER_ERROR | SHA-1 **debug** (atau **release**) yang dipakai build ada di Firebase; `google-services.json` terbaru; `oauth_client` tidak kosong. |
| iOS redirect / “invalid client” | `REVERSED_CLIENT_ID` di **Info.plist** URL schemes; plist & Bundle ID cocok dengan Firebase. |
| Login Google berhasil, snackbar “nomor belum terverifikasi” | Perilaku sengaja: user harus menyelesaikan **daftar Google + OTP** (nomor ter-*link* di Firebase Auth). |

Dokumen terkait OTP: [`FIREBASE_OTP_LANGKAH.md`](FIREBASE_OTP_LANGKAH.md).
