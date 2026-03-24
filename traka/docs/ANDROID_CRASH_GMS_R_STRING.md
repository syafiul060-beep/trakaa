# Crash: `NoClassDefFoundError` — `com.google.android.gms.common.R$string`

## Gejala

- Logcat: `FATAL EXCEPTION: main` → `Failed resolution of: Lcom/google/android/gms/common/R$string`
- Stack: `FirebaseApp.initializeApp` → `FirebaseOptions.fromResource` → `StringResourceValueReader`
- App: splash lalu langsung tutup.

## Penyebab

Kelas resource `R$string` dari **Google Play Services (common)** tidak ada di APK saat runtime — sering karena versi transitif `play-services-base` / **basement** tidak sejajar atau tidak terpaket.

## Perbaikan di proyek

Di `android/app/build.gradle.kts` sudah ditambahkan dependensi eksplisit:

- `com.google.android.gms:play-services-base:18.9.0`
- `com.google.android.gms:play-services-basement:18.9.0`

Setelah mengubah Gradle: `flutter clean` → `flutter pub get` → build/run lagi.

## Jika masih crash

- Pastikan **Google Play Store** / **Google Play services** di HP ter-update.
- `flutter clean`, hapus folder `build`, rebuild.
- Ambil logcat penuh dan bandingkan dengan error baru.
