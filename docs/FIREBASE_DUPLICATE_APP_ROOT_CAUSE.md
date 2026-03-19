# Root Cause: Firebase [core/duplicate-app] Error

## Ringkasan

Error `[core/duplicate-app] A Firebase App named "[DEFAULT]" already exists` terjadi karena **Firebase diinisialisasi dua kali** dari dua sumber berbeda.

---

## Sumber Masalah (Root Cause)

### 1. **FirebaseInitProvider (Native Android)** — Inisialisasi Pertama

| Aspek | Detail |
|-------|--------|
| **Apa** | `FirebaseInitProvider` — ContentProvider bawaan Firebase Android SDK |
| **Kapan** | Otomatis saat app startup, **sebelum** `Application.onCreate()` dan **sebelum** Flutter/Dart berjalan |
| **Dari mana** | Di-merge ke AndroidManifest oleh Gradle (dari dependency `firebase-analytics`, `firebase-crashlytics`, dll.) |
| **Konfigurasi** | Membaca dari `google-services.json` (diproses plugin `com.google.gms.google-services`) |
| **Urutan** | Application dibuat → ContentProvider di-init (termasuk FirebaseInitProvider) → Firebase sudah ada |

### 2. **main.dart (Dart)** — Inisialisasi Kedua

| Aspek | Detail |
|-------|--------|
| **Apa** | `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` |
| **Kapan** | Saat `main()` dijalankan, setelah Flutter engine siap |
| **Konfigurasi** | Dari `firebase_options.dart` (FlutterFire CLI) |
| **Urutan** | FirebaseInitProvider sudah jalan → main() jalan → kita panggil initializeApp lagi → **duplicate-app** |

### Alur yang Menyebabkan Error

```
App Start
    │
    ├─► FirebaseInitProvider.onCreate()  ← Init #1 (dari google-services.json)
    │       └─► FirebaseApp [DEFAULT] sudah ada
    │
    ├─► Flutter engine start
    │
    └─► main() di Dart
            └─► Firebase.initializeApp()  ← Init #2 (dari firebase_options.dart)
                    └─► ERROR: [DEFAULT] already exists
```

---

## Bukti di Codebase

### build.gradle.kts
```kotlin
id("com.google.gms.google-services")   // Proses google-services.json
implementation("com.google.firebase:firebase-analytics")  // Bawa FirebaseInitProvider
implementation("com.google.firebase:firebase-crashlytics")
```

### google-services.json
- Ada di `android/app/google-services.json`
- API key: `AIzaSyB7Qh7jTbAb_SfVNNbEuO0XutQ0dJIZr8U`
- App ID: `1:652861002574:android:01af2236f206639950041f`

### firebase_options.dart
- API key Android: `AIzaSyD7Jz7Cs4UKlOWT2Ztr7LulhlNuHV0hOlA` (berbeda!)
- App ID: sama

**Catatan:** Perbedaan API key antara `google-services.json` dan `firebase_options.dart` bisa jadi dari rotasi key. Yang penting: dua sumber konfigurasi → dua inisialisasi → duplicate-app.

---

## Solusi yang Diterapkan (Opsi B)

**FirebaseInitProvider tetap aktif** agar Crashlytics bisa menangkap crash native awal. Duplicate-app ditangani di Dart.

### Penanganan Error Duplicate di Dart

Di `main.dart` dan `fcm_service.dart`:
- Catch error saat `Firebase.initializeApp()`
- Jika pesan mengandung `duplicate-app` atau `already exists` → anggap sukses, lanjut
- FirebaseInitProvider sudah init dari native → kita skip, app berjalan normal

---

## Rekomendasi Tambahan

1. **Sinkronkan konfigurasi** — Jalankan `flutterfire configure` agar `firebase_options.dart` dan `google-services.json` konsisten.

2. **Full rebuild** setelah perubahan:
   ```bash
   flutter clean && flutter pub get && flutter run
   ```

3. **Uninstall app** dari device sebelum install ulang (clear state lama).
