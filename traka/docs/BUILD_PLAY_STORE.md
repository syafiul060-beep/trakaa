# Build Traka untuk Google Play Store

Build di **laptop RAM/CPU terbatas** atau error **file `R.jar` terkunci**: lihat [`BUILD_LAPTOP_LEMAH.md`](BUILD_LAPTOP_LEMAH.md).

**Strategi navigasi (Target A vs B, langkah eksekusi):** [`NAVIGASI_TARGET_PRODUK_VS_GOOGLE_MAPS.md`](NAVIGASI_TARGET_PRODUK_VS_GOOGLE_MAPS.md).

---

## Persiapan

### 1. Versi

Di `pubspec.yaml`, contoh: `version: 1.1.0+11`:
- **1.1.0** = versionName (yang tampil di Play Store)
- **+11** = versionCode (harus naik tiap upload baru ke Play Store)

**Penting:** Tiap upload baru, naikkan angka setelah `+`:

```yaml
version: 1.1.0+12   # contoh untuk setelah 1.1.0+11

### 2. Signing (key.properties)

Pastikan file `android/key.properties` ada dan berisi:

```properties
storePassword=password_keystore_anda
keyPassword=password_key_anda
keyAlias=upload
storeFile=upload-keystore.jks
```

Dan file `upload-keystore.jks` ada di folder `android/` (atau sesuaikan path di `storeFile`).

Tambahkan juga baris `MAPS_API_KEY=...` di file yang sama jika dipakai untuk rute (bisa digabung dengan signing di satu `key.properties`).

**Penting:** `build.gradle.kts` **tidak** memakai debug keystore untuk `bundleRelease` / `assembleRelease`. Jika keystore belum lengkap atau file `.jks` tidak ada, Gradle akan **gagal di awal** dengan pesan jelas — supaya AAB/APK release tidak ter-upload ke Play Store dengan signing salah.

> Jika sudah pernah build ke Play Store, file ini biasanya sudah ada. Jangan commit ke Git.

---

## Langkah Build

### 1. Bersihkan build lama

```batch
cd D:\Traka\traka
flutter clean
flutter pub get
```

### 2. Build App Bundle (format untuk Play Store)

**Disarankan (hybrid API + Redis di produksi):** dari folder `traka`, supaya `MAPS_API_KEY` ikut dari `android/key.properties`:

```powershell
.\scripts\build_hybrid.ps1 -Target appbundle
```

Setara manual (sesuaikan URL API produksi):

```batch
flutter build appbundle --release --dart-define=TRAKA_API_BASE_URL=https://trakaa-production.up.railway.app --dart-define=TRAKA_USE_HYBRID=true --dart-define=MAPS_API_KEY=ISI_DARI_key.properties
```

Tanpa `TRAKA_USE_HYBRID` + URL, release hanya memakai **Firestore** untuk status driver / matching (aman, tapi bukan jalur hybrid penuh). Pinning opsional: `.\scripts\build_hybrid.ps1 -Target appbundle -CertSha256 "AA:BB:..."`.

**Hanya Firestore (tanpa hybrid API):**

```batch
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

> Gunakan **appbundle** (.aab), bukan APK. Play Store meminta AAB sejak 2021.

### 3. Jika Gradle error / stuck

```batch
cd D:\Traka\traka\android
gradlew --stop
cd ..
flutter build appbundle --release
```

Untuk hybrid, ulangi argumen `--dart-define=...` yang sama seperti di langkah 2, atau pakai `build_hybrid.ps1`.

Lihat juga `docs/BUILD_STUCK_SOLUSI.md` dan `docs/BUILD_TANPA_DAEMON.md` jika ada masalah.

---

## File deobfuscation (ProGuard / R8) — peringatan Play Console

Release build memakai **R8** (`minifyEnabled true`). Setelah `flutter build appbundle --release`, Gradle menghasilkan:

- **`build/app/outputs/mapping/release/mapping.txt`** — dipakai Play Console untuk menerjemahkan stack trace yang ter-obfuscate.

**Upload ke Play Console (disarankan untuk hilangkan pesan “Tidak ada file deobfuscation…”):**

1. Saat **Buat rilis** / **Edit rilis**, setelah upload `.aab`, cari bagian **Deobfuscation file** / **ProGuard mapping** / **App bundle explorer** (nama menu bisa sedikit berbeda).
2. Upload file **`mapping.txt`** dari path di atas (versi harus sama dengan AAB yang di-upload).

**Firebase Crashlytics:** Di `android/app/build.gradle.kts` sudah ada `mappingFileUploadEnabled = true` agar mapping ikut ter-upload ke Crashlytics saat build (stack trace di Firebase lebih terbaca).

Jika build release gagal atau crash saat runtime setelah R8, laporkan error Gradle / logcat; bisa ditambah aturan di `android/app/proguard-rules.pro`.

---

## Upload ke Play Console

1. Buka [Google Play Console](https://play.google.com/console)
2. Pilih aplikasi **Traka**
3. **Production** (atau **Internal testing** / **Closed testing** untuk uji dulu)
4. **Create new release**
5. Upload file: `build/app/outputs/bundle/release/app-release.aab`
6. **Upload `mapping.txt`** (lihat bagian di atas) untuk versi yang sama
7. Isi **Release notes** (perubahan di versi ini)
8. **Review release** → **Start rollout**

---

## Ringkasan Cepat

**Aplikasi hybrid (disarankan untuk rilis Play Store)** — menyertakan `TRAKA_API_BASE_URL`, `TRAKA_USE_HYBRID`, dan `MAPS_API_KEY` dari `android/key.properties`:

```batch
cd D:\Traka\traka
flutter clean
flutter pub get
.\scripts\build_hybrid.bat -Target appbundle
```

Opsional: URL API lain, mis. `.\scripts\build_hybrid.bat -Target appbundle -ApiUrl "https://api-anda.com"`.

File hasil: `build\app\outputs\bundle\release\app-release.aab`

**Tanpa skrip hybrid** (`flutter build appbundle --release` saja) **tidak** menginjeksi define hybrid kecuali Anda set manual — untuk produksi biasanya **salah**.

---

### Alternatif (setara manual)

```batch
flutter build appbundle --release --dart-define=TRAKA_API_BASE_URL=https://... --dart-define=TRAKA_USE_HYBRID=true --dart-define=MAPS_API_KEY=...
```
