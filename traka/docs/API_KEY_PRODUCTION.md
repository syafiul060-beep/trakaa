# API Key untuk Production – Panduan Terperinci

Dokumen ini menjelaskan cara mengamankan API key Google Maps untuk aplikasi Traka di production.

---

## Yang Harus Dilakukan (Ringkas)

Jika Anda ingin pakai **API key baru** untuk production (agar key lama yang terpapar tidak disalahgunakan):

### Untuk Android (wajib jika build APK/AAB)

1. Buka file **`traka/android/key.properties`** (jika belum ada, salin dari `key.properties.example`).
2. Tambahkan baris ini (ganti dengan API key baru Anda):

   ```
   MAPS_API_KEY=AIzaSy_xxx_key_anda
   ```

3. Simpan. Build seperti biasa: `flutter build apk` atau `flutter build appbundle`.

### Untuk iOS (jika deploy ke App Store)

1. Buka file **`traka/ios/Runner/AppDelegate.swift`**.
2. Cari baris: `GMSServices.provideAPIKey("...")`.
3. Ganti string di dalam tanda kutip dengan API key baru Anda.
4. Simpan. Build: `flutter build ios`.

### Di Google Cloud Console

1. Buat API key baru di [Credentials](https://console.cloud.google.com/apis/credentials).
2. Restrict key: pilih **Android apps** (package name: `id.traka.app`) dan/atau **iOS apps** (bundle ID: `com.example.traka`).
3. Centang API: Maps SDK for Android, Maps SDK for iOS, Directions API.
4. Setelah deploy berhasil, nonaktifkan key lama.

---

**Selesai.** Tidak perlu ubah kode atau build.gradle — aplikasi sudah siap.

---

## Status Implementasi

| Komponen | Status | Yang perlu dilakukan |
|----------|--------|----------------------|
| **Android** | Sudah siap | Cukup tambah baris `MAPS_API_KEY=...` di `key.properties` |
| **Dart (Directions)** | Sudah siap | Otomatis pakai key yang sama atau fallback |
| **.gitignore** | Sudah | key.properties tidak akan ter-commit |
| **iOS** | Manual | Ganti key di `AppDelegate.swift` |

---

## Daftar Isi

1. [Ringkasan & Alur Key](#1-ringkasan--alur-key)
2. [Android: key.properties](#2-android-keyproperties)
3. [Android: Environment Variable (CI/CD)](#3-android-environment-variable-cicd)
4. [Directions API (Dart)](#4-directions-api-dart)
5. [iOS: AppDelegate.swift](#5-ios-appdelegateswift)
6. [iOS: CI/CD dengan xcconfig](#6-ios-cicd-dengan-xcconfig)
7. [Rotasi Key di Google Cloud Console](#7-rotasi-key-di-google-cloud-console)
8. [Restrict Key (Keamanan)](#8-restrict-key-keamanan)
9. [Verifikasi & Troubleshooting](#9-verifikasi--troubleshooting)
10. [Cek .gitignore](#10-cek-gitignore)

---

## 1. Ringkasan & Alur Key

Aplikasi Traka memakai Google Maps di **3 tempat**:

| Lokasi | File | Fungsi |
|--------|------|--------|
| **Maps SDK Android** | `android/app/src/main/AndroidManifest.xml` | Menampilkan peta di HP Android |
| **Maps SDK iOS** | `ios/Runner/AppDelegate.swift` | Menampilkan peta di iPhone |
| **Directions API** | `lib/config/maps_config.dart` | HTTP request untuk rute/navigasi |

**Urutan prioritas** saat build:

- **Android Manifest:** `key.properties` → env `MAPS_API_KEY` → fallback default (key aplikasi Traka)
- **Dart (Directions):** `--dart-define=MAPS_API_KEY` → fallback default (key aplikasi Traka)

**Identitas aplikasi** (untuk restrict key):

- **Android:** `id.traka.app`
- **iOS:** `com.example.traka` (atau bundle ID di `ios/Runner.xcodeproj/project.pbxproj`)

---

## 2. Android: key.properties

**Catatan:** `build.gradle.kts` dan `AndroidManifest.xml` sudah dikonfigurasi. Anda hanya perlu menambah baris di `key.properties`.

### 2.1 Lokasi file

- **Path:** `traka/android/key.properties`
- **Contoh:** `traka/android/key.properties.example` (jangan pakai langsung, salin dulu)

### 2.2 Langkah detail

**Langkah 1:** Pastikan file `key.properties` ada

```bash
# Dari root project Traka
cd traka/android

# Jika belum ada, salin dari contoh
copy key.properties.example key.properties   # Windows
# atau
cp key.properties.example key.properties     # Linux/Mac
```

**Langkah 2:** Buka `key.properties` dengan editor teks

**Langkah 3:** Tambahkan baris berikut (ganti `AIzaSy_xxx` dengan API key Anda):

```properties
# Opsional: API key Google Maps (untuk production)
MAPS_API_KEY=AIzaSy_xxx_key_baru_anda
```

**Contoh isi lengkap** `key.properties`:

```properties
# Signing (wajib untuk release)
storePassword=password_keystore_anda
keyPassword=password_key_anda
keyAlias=upload
storeFile=upload-keystore.jks

# Maps API key (opsional, untuk production)
MAPS_API_KEY=AIzaSy_xxx_key_baru_anda
```

**Langkah 4:** Simpan file. Jangan commit ke Git.

**Langkah 5:** Build aplikasi

```bash
cd traka
flutter build apk
# atau untuk Play Store
flutter build appbundle
```

### 2.3 Cara kerja di Gradle

File `android/app/build.gradle.kts` membaca key dengan urutan:

1. `keystoreProperties["MAPS_API_KEY"]` dari `key.properties`
2. `System.getenv("MAPS_API_KEY")` dari environment
3. Fallback ke key default (jika keduanya kosong)

Nilai tersebut dimasukkan ke `AndroidManifest.xml` via `manifestPlaceholders["mapsApiKey"]`.

---

## 3. Android: Environment Variable (CI/CD)

Untuk build otomatis (GitHub Actions, GitLab CI, dll.), pakai environment variable.

### 3.1 Windows (PowerShell)

```powershell
# Set untuk session saat ini
$env:MAPS_API_KEY="AIzaSy_xxx_key_anda"

# Verifikasi
echo $env:MAPS_API_KEY

# Build
cd d:\Traka\traka
flutter build apk
```

### 3.2 Windows (Command Prompt)

```cmd
set MAPS_API_KEY=AIzaSy_xxx_key_anda
flutter build apk
```

### 3.3 Linux / Mac / Bash

```bash
export MAPS_API_KEY=AIzaSy_xxx_key_anda
flutter build apk
```

### 3.4 GitHub Actions (contoh)

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - name: Build APK
        env:
          MAPS_API_KEY: ${{ secrets.MAPS_API_KEY }}
        run: |
          cd traka
          flutter build apk
```

**Catatan:** Simpan `MAPS_API_KEY` di **Settings → Secrets and variables → Actions** sebagai secret.

---

## 4. Directions API (Dart)

Key untuk HTTP calls (Directions API) dibaca di `lib/config/maps_config.dart` dari `--dart-define`.

### 4.1 Build dengan dart-define

```bash
cd traka

# APK
flutter build apk --dart-define=MAPS_API_KEY=AIzaSy_xxx_key_anda

# App Bundle (Play Store)
flutter build appbundle --dart-define=MAPS_API_KEY=AIzaSy_xxx_key_anda
```

### 4.2 Kapan dipakai

- Jika **sama** dengan Maps SDK: cukup set di `key.properties` (Android) dan `AppDelegate.swift` (iOS). Directions API akan pakai fallback dari `MapsConfig` (key default di kode).
- Jika **berbeda**: wajib pakai `--dart-define=MAPS_API_KEY=...` saat build.

### 4.3 CI/CD dengan dart-define

```yaml
- name: Build
  run: |
    flutter build apk --dart-define=MAPS_API_KEY=${{ secrets.MAPS_API_KEY }}
```

---

## 5. iOS: AppDelegate.swift

**Catatan:** iOS belum punya dukungan env/xcconfig. Ganti key secara manual di file ini.

### 5.1 Lokasi file

`traka/ios/Runner/AppDelegate.swift`

### 5.2 Langkah manual

**Langkah 1:** Buka file di editor

**Langkah 2:** Cari baris:

```swift
GMSServices.provideAPIKey("AIzaSyCsF6MXsNwo1qVjUHtTyjlTmW7IC8XPwWg")
```

**Langkah 3:** Ganti string di dalam tanda kutip dengan API key baru:

```swift
GMSServices.provideAPIKey("AIzaSy_xxx_key_baru_anda")
```

**Langkah 4:** Simpan

**Langkah 5:** Build

```bash
cd traka
flutter build ios
```

### 5.3 Peringatan

- Jangan commit `AppDelegate.swift` yang berisi key production ke repo publik.
- Untuk tim: pertimbangkan `xcconfig` atau build phase yang baca dari env (lihat bagian 6).

---

## 6. iOS: CI/CD dengan xcconfig (Opsional)

Untuk build otomatis tanpa hardcode key. **Tidak wajib** — bisa tetap ganti manual di AppDelegate.swift.

### 6.1 Buat file xcconfig

Buat `ios/Config/Secrets.xcconfig` (jangan di-commit):

```
MAPS_API_KEY = AIzaSy_xxx_key_anda
```

Tambahkan ke `.gitignore`:

```
ios/Config/Secrets.xcconfig
```

### 6.2 Include di project

Di `ios/Flutter/Release.xcconfig` (atau `Debug.xcconfig`), tambahkan:

```
#include? "Config/Secrets.xcconfig"
```

### 6.3 Pakai di AppDelegate (Swift)

Ubah `AppDelegate.swift`:

```swift
let mapsKey = Bundle.main.object(forInfoDictionaryKey: "MAPS_API_KEY") as? String ?? ""
GMSServices.provideAPIKey(mapsKey)
```

Lalu tambahkan `MAPS_API_KEY` ke `Info.plist` dari xcconfig (via build setting).

### 6.4 Alternatif: sed di script (Linux/Mac)

```bash
# Ganti key di AppDelegate dari env
MAPS_API_KEY="AIzaSy_xxx"
sed -i.bak "s/GMSServices.provideAPIKey(\".*\")/GMSServices.provideAPIKey(\"$MAPS_API_KEY\")/" ios/Runner/AppDelegate.swift
flutter build ios
```

---

## 7. Rotasi Key di Google Cloud Console

Lakukan jika key pernah terpapar (misalnya ter-commit ke Git).

### 7.1 Langkah 1: Buka Google Cloud Console

1. Buka [https://console.cloud.google.com/](https://console.cloud.google.com/)
2. Login dengan akun Google project Traka
3. Pilih **project** yang dipakai Firebase Traka

### 7.2 Langkah 2: Buka Credentials

1. Menu kiri: **APIs & Services** → **Credentials**
2. Di bagian **API keys**, akan terlihat daftar key

### 7.3 Langkah 3: Buat key baru

1. Klik **+ CREATE CREDENTIALS**
2. Pilih **API key**
3. Key baru akan muncul; **salin** dan simpan di tempat aman

### 7.4 Langkah 4: Restrict key baru

1. Klik key yang baru dibuat (atau **Edit**)
2. Isi **Application restrictions** dan **API restrictions** (lihat [bagian 8](#8-restrict-key-keamanan))

### 7.5 Langkah 5: Update aplikasi

1. Update `android/key.properties` dengan key baru
2. Update `ios/Runner/AppDelegate.swift` dengan key baru
3. Jika pakai `--dart-define`, update di CI/CD
4. Build dan deploy aplikasi

### 7.6 Langkah 6: Nonaktifkan key lama

1. Setelah deploy berhasil, kembali ke **Credentials**
2. Klik key lama
3. Klik **Disable** (atau **Delete** jika yakin)

---

## 8. Restrict Key (Keamanan)

Restrict key agar hanya dipakai oleh aplikasi Traka.

### 8.1 Application restrictions

**Android:**

1. Pilih **Android apps**
2. Klik **Add an item**
3. Isi:
   - **Package name:** `id.traka.app`
   - **SHA-1 certificate fingerprint:** dari keystore release (lihat `keytool -list -v -keystore upload-keystore.jks`)

**iOS:**

1. Pilih **iOS apps**
2. Klik **Add an item**
3. Isi **Bundle ID:** `com.example.traka` (atau bundle ID yang dipakai di Xcode)

### 8.2 API restrictions

1. Pilih **Restrict key**
2. Centang:
   - **Maps SDK for Android**
   - **Maps SDK for iOS**
   - **Directions API**
   - **Geocoding API** (jika dipakai)
3. Simpan

### 8.3 Referensi SHA-1

```bash
# Debug (development)
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android

# Release (upload-keystore.jks)
keytool -list -v -keystore android/upload-keystore.jks -alias upload
```

---

## 9. Verifikasi & Troubleshooting

### 9.1 Verifikasi key terpakai

**Android:**

1. Build: `flutter build apk`
2. Ekstrak APK dan cek `AndroidManifest.xml` di dalamnya
3. Cari `com.google.android.geo.API_KEY` — nilai harus key yang Anda set

**Dart:**

- Tambahkan `debugPrint(MapsConfig.directionsApiKey)` di `main.dart` (hapus setelah cek)
- Pastikan output sesuai key yang diharapkan

### 9.2 Error umum

| Error | Penyebab | Solusi |
|-------|----------|--------|
| Peta blank / tidak muncul | Key salah atau tidak di-restrict | Cek key di Console, pastikan Maps SDK aktif |
| "This API key is not authorized" | Restrict terlalu ketat | Pastikan package name / bundle ID / SHA-1 sesuai |
| "API key not valid" | Key salah atau expired | Buat key baru dan restrict |
| Build gagal: mapsApiKey kosong | `key.properties` tidak terbaca | Cek path `android/key.properties`, pastikan `MAPS_API_KEY` ada |

### 9.3 Cek API yang aktif

Di Google Cloud Console: **APIs & Services** → **Enabled APIs & services**

Pastikan aktif:

- Maps SDK for Android
- Maps SDK for iOS
- Directions API
- Geocoding API (jika dipakai)

---

## 10. Cek .gitignore

**Sudah dikonfigurasi** di `traka/android/.gitignore`:

```
key.properties
**/*.jks
```

### 10.2 Verifikasi

```bash
git status
# key.properties tidak boleh muncul. Jika muncul, cek .gitignore.
```

### 10.3 Jika key.properties sudah pernah ter-commit

1. Hapus dari Git: `git rm --cached traka/android/key.properties`
2. Pastikan ada di `.gitignore`
3. **Rotasi key** — key yang pernah ter-commit dianggap bocor

---

## Checklist Singkat

**Konfigurasi (manual):**

- [ ] `android/key.properties` — tambah baris `MAPS_API_KEY=...` (atau set env saat build)
- [ ] `ios/Runner/AppDelegate.swift` — ganti key di `GMSServices.provideAPIKey(...)`
- [ ] Key di-restrict di Google Cloud Console (Android apps + iOS apps + API restrictions)

**Sudah ada (tidak perlu ubah):**

- [x] `build.gradle.kts` — sudah baca MAPS_API_KEY
- [x] `AndroidManifest.xml` — sudah pakai placeholder
- [x] `MapsConfig` (Dart) — sudah baca dari dart-define
- [x] `.gitignore` — key.properties dan *.jks sudah di-ignore

**Jika key pernah terpapar:** buat key baru, deploy, nonaktifkan key lama

