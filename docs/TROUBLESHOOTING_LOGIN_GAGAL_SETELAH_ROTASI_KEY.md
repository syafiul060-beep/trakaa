# Troubleshooting: Login Gagal Setelah Rotasi API Key

## Penyebab Umum

Setelah rotasi API key, login bisa gagal karena:

1. **API key restrictions** — Key baru belum punya izin API yang benar
2. **SHA-1 fingerprint** — Key Android terbatas SHA-1, tapi SHA-1 belum ditambah
3. **Firebase Console** — SHA-1/SHA-256 belum didaftar untuk Phone Auth
4. **App Check** — Blokir request jika konfigurasi belum sesuai

---

## Checklist Perbaikan

### 1. Cek API Restrictions di Key Android (PENTING)

Key `AIzaSyD7Jz7Cs4UKlOWT2Ztr7LulhlNuHV0hOlA` (key android) harus mengizinkan API Firebase:

1. Buka [Google Cloud Console](https://console.cloud.google.com/) → **APIs & Services** → **Credentials**
2. Klik **key android**
3. Di **API restrictions**:
   - **Pilihan termudah:** Pilih **"Don't restrict key"** → Simpan (key hanya dilindungi oleh Application restrictions)
   - **Jika "Restrict key":** Tambahkan minimal:
     - **Identity Toolkit API** (Firebase Auth)
     - **Cloud Functions API** (getPhoneLoginEmail, checkEmailExists)
     - **Firebase Installations API**
     - **Token Service API**

### 2. Cek Application Restrictions di Key Android

Jika key di-restrict ke **Android apps**:

1. Package name harus: `id.traka.app`
2. **SHA-1 certificate fingerprint** harus sesuai build:
   - **Debug build:** SHA-1 dari debug keystore
   - **Release build:** SHA-1 dari upload-keystore.jks

**Ambil SHA-1:**
```bash
# Debug (flutter run)
keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android

# Release
keytool -list -v -keystore traka/android/upload-keystore.jks -alias upload
```

Tambahkan SHA-1 yang muncul ke **Application restrictions** → Android apps → Add fingerprint.

### 3. Tambah SHA-1 & SHA-256 di Firebase Console

Penting untuk **Phone Auth** dan **Play Integrity**:

1. Firebase Console → **Project settings** (ikon roda) → **Your apps**
2. Pilih app Android `id.traka.app`
3. Klik **Add fingerprint** → tempel **SHA-1**
4. Klik **Add fingerprint** lagi → tempel **SHA-256**
5. **Download ulang** `google-services.json` → ganti file di `traka/android/app/`

### 4. Nonaktifkan App Check Sementara (untuk uji)

Jika App Check memblokir:

1. Firebase Console → **Firestore** → collection `app_config` → doc `settings`
2. Set field `appCheckEnabled` = `false`
3. Coba login lagi

### 5. Cek Error di Log

Jalankan dengan:
```bash
flutter run
```

Saat login gagal, perhatikan log di terminal. Cari:
- `FirebaseAuthException` + `e.code` (mis. `invalid-credential`, `app-not-verified`)
- `FirebaseFunctionsException` (mis. `unauthenticated`, `permission-denied`)

---

## Ringkasan Cepat

| Gejala | Kemungkinan Penyebab | Solusi |
|--------|----------------------|--------|
| "Gagal login. Silakan coba lagi." | Functions/Auth error umum | Cek API restrictions, SHA-1 |
| "Perangkat/aplikasi belum terverifikasi" | SHA-1 belum di Firebase | Tambah SHA-1 di Firebase Console |
| "This API key is not authorized" | Key restrict terlalu ketat | Tambah SHA-1 di GCP Credentials |
| Functions timeout / unauthenticated | App Check | Nonaktifkan sementara atau perbaiki App Check |

---

## Setelah Perbaikan

1. `flutter clean`
2. `flutter pub get`
3. Uninstall app dari device
4. `flutter run` (atau build ulang)
