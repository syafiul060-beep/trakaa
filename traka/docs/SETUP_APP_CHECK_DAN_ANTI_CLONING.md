# Setup Firebase App Check & Proteksi Anti-Cloning

Dokumen ini menjelaskan langkah mengaktifkan Firebase App Check dan membatasi API key untuk mencegah akses dari aplikasi kloning.

## 1. Firebase App Check

App Check memastikan bahwa request ke Firebase (Firestore, Auth, Storage, Functions) hanya berasal dari aplikasi resmi Traka.

### Langkah di Firebase Console

1. Buka [Firebase Console](https://console.firebase.google.com/) → pilih project **syafiul-traka**
2. Masuk ke **Project Settings** (ikon gear) → **App Check**
3. Klik **Register** untuk setiap app (Android, iOS)

#### Android (Play Integrity)

- Pilih app Android (`id.traka.app`)
- Provider: **Play Integrity**
- Tambahkan **SHA-256** dari signing key release Anda:
  - Debug: `keytool -list -v -keystore ~/.android/debug.keystore`
  - Release: dari `key.properties` Anda
- Simpan

#### iOS (App Attest)

- Pilih app iOS
- Provider: **App Attest** (iOS 14+)
- Simpan

#### Debug provider (untuk development)

- Di App Check, klik **Manage debug tokens**
- Generate debug token
- Tambahkan token ke project (untuk testing di emulator/device tanpa Play Store)

### Kode di aplikasi

App Check diinisialisasi di `lib/main.dart` **jika diaktifkan via web admin**:

- Buka **traka-admin** → **Pengaturan** → **App Check** → centang "Aktifkan App Check di aplikasi mobile"
- Simpan. Nilai disimpan di Firestore `app_config/settings.appCheckEnabled`
- Aplikasi mobile membaca config saat startup dan mengaktifkan App Check hanya jika `appCheckEnabled === true`
- **Debug build** (`flutter run`): pakai `AndroidProvider.debug` / `AppleProvider.debug`
- **Release build**: pakai `AndroidProvider.playIntegrity` / `AppleProvider.appAttest`

Untuk testing di emulator, daftarkan **debug token** di Firebase Console dan pastikan build debug.

**Menonaktifkan App Check**: Centang off di web admin, lalu pastikan enforcement di Firebase Console juga OFF (Project Settings → App Check → per produk).

### Aktifkan enforcement (bertahap)

1. **Monitor dulu**: Di App Check, lihat metrik request (berapa % yang punya token valid)
2. **Enforcement**: Setelah yakin, aktifkan enforcement untuk:
   - Cloud Firestore
   - Firebase Authentication
   - Cloud Storage
   - Cloud Functions (lihat di bawah)

### Cloud Functions – App Check

Di `functions/index.js` sudah ada konfigurasi:

```javascript
const ENFORCE_APP_CHECK = true; // Tahap 4: aktif
const callable = ENFORCE_APP_CHECK
  ? functions.runWith({ enforceAppCheck: true }).https
  : functions.https;
```

Semua callable function memakai `callable.onCall(...)`. **App Check enforcement sudah aktif** (Tahap 4):

- Request tanpa token App Check valid akan ditolak (error `unauthenticated`)
- Hanya app resmi Traka (Play Integrity / App Attest) yang bisa memanggil Cloud Functions

**Rollback**: Jika device tertentu gagal (custom ROM, dll), set `ENFORCE_APP_CHECK = false` dan deploy ulang.

---

## 2. Restrict API Key di Google Cloud Console

Batasi API key agar hanya bisa dipakai oleh app dengan package name `id.traka.app`.

### Langkah

1. Buka [Google Cloud Console](https://console.cloud.google.com/) → pilih project **syafiul-traka**
2. **APIs & Services** → **Credentials**
3. Cari API key yang dipakai Firebase (biasanya "Browser key" atau "Android key")
4. Klik edit (ikon pensil)
5. Di **Application restrictions**:
   - **Android apps**: tambah package name `id.traka.app` + SHA-1 fingerprint
   - **iOS apps**: tambah bundle ID (mis. `com.example.traka` atau `id.traka.app`)
6. Di **API restrictions**: pilih "Restrict key" → centang hanya API yang dipakai (Firebase, Maps, dll.)
7. Simpan

---

## 3. Ringkasan proteksi

| Lapisan | Fungsi |
|---------|--------|
| **SHA-1 di Firebase** | Hanya app yang di-sign dengan keystore Anda yang bisa connect |
| **Firebase App Check** | Verifikasi app asli (Play Integrity / App Attest) |
| **API key restrictions** | Batasi penggunaan API key per package/bundle |
| **Root/jailbreak detection** | Blokir device yang di-root/jailbreak |

---

## 4. Catatan

- **Play Integrity** hanya berjalan untuk app yang didistribusikan via **Google Play**. Untuk testing internal, pakai debug provider.
- Setelah enforcement aktif, app kloning (package name / signing key berbeda) tidak akan bisa akses Firebase project Anda.
- Jangan simpan API key rahasia (service account) di client – simpan di backend (Cloud Functions, env vars).
