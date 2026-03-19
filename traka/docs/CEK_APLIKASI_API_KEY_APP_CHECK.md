# Cek Aplikasi: API Key & App Check

**Tanggal:** 19 Maret 2026  
**Status:** Verifikasi setelah rotasi API key dan masalah App Check

---

## Ringkasan Status

| Komponen | Status | Catatan |
|----------|--------|---------|
| **Firebase API keys** | ✅ | firebase_options, google-services.json sinkron |
| **Maps API key** | ✅ | key.properties + run_hybrid.ps1 |
| **App Check (Functions)** | ✅ | ENFORCE_APP_CHECK = false (login jalan) |
| **App Check (Flutter)** | ✅ | Debug: debug token, Release: Play Integrity |
| **Duplicate-app handling** | ✅ | main.dart + fcm_service.dart |
| **Directions API** | ✅ | MAPS_API_KEY diteruskan via run_hybrid.ps1 |

---

## 1. API Key – Sudah Benar

### Firebase (traka/lib/firebase_options.dart)
- **Web:** `AIzaSyAL9LaqOBn6vjC_D9xK02Afnl68s6BkXJU` (browser)
- **Android:** `AIzaSyD7Jz7Cs4UKlOWT2Ztr7LulhlNuHV0hOlA`
- **iOS:** `AIzaSyBlirfTyEZ2nQYNRyNFPH4w4N7DHP3eip8`

### Android (google-services.json)
- `current_key`: `AIzaSyD7Jz7Cs4UKlOWT2Ztr7LulhlNuHV0hOlA` ✓

### Maps (key.properties)
- `MAPS_API_KEY`: `AIzaSyBhWS2y8VVrsNEikCIv13y829WYXZGBPvw` ✓

### Verifikasi run_hybrid.ps1
```
MAPS_API_KEY: AIzaSyBhWS...
```
Key terbaca dan diteruskan ke Flutter ✓

---

## 2. App Check – Konfigurasi Saat Ini

### Cloud Functions (functions/index.js)
```javascript
const ENFORCE_APP_CHECK = false;
```
- **Login:** Berjalan normal (tidak enforce App Check)
- **Alasan:** Saat `true`, login gagal (unauthenticated) karena token App Check belum valid di production

### Flutter (main.dart)
- **Debug:** App Check aktif dengan `AndroidProvider.debug` / `AppleProvider.debug`
- **Release:** App Check aktif dengan `AndroidProvider.playIntegrity` / `AppleProvider.appAttest`
- **Config:** Baca dari Firestore `app_config/settings.appCheckEnabled`

### Kapan Aktifkan ENFORCE_APP_CHECK?
1. Daftarkan debug token di Firebase Console (untuk development)
2. Pastikan Play Integrity / App Attest berjalan di production
3. Set `ENFORCE_APP_CHECK = true` di functions/index.js
4. Deploy: `firebase deploy --only functions`

---

## 3. Duplicate-App Handling

### main.dart
- `Firebase.initializeApp` dibungkus try-catch
- Jika error `duplicate-app` → lanjut (Firebase sudah di-init native)
- Error lain → tampilkan _ErrorApp

### fcm_service.dart
- Background handler cek `Firebase.apps.isEmpty` sebelum init
- Jika init gagal dengan duplicate-app → tidak rethrow

---

## 4. Cara Menjalankan yang Benar

```powershell
cd d:\Traka\traka
.\scripts\run_hybrid.ps1
```

**Penting:** Jika ada banyak device, pilih satu:
```powershell
flutter devices
.\scripts\run_hybrid.ps1
# Lalu tambahkan -d <deviceId> di script, atau:
flutter run -d windows --dart-define=TRAKA_API_BASE_URL=https://trakaa-production.up.railway.app --dart-define=TRAKA_USE_HYBRID=true --dart-define=MAPS_API_KEY=AIzaSyBhWS2y8VVrsNEikCIv13y829WYXZGBPvw
```

---

## 5. Checklist Jika Masih Bermasalah

### Login gagal
- [ ] ENFORCE_APP_CHECK = false di functions/index.js
- [ ] Deploy functions: `firebase deploy --only functions`
- [ ] Cek firebase_options.dart pakai key Android yang benar

### Rute gagal dimuat
- [ ] Jalankan via `run_hybrid.ps1` (bukan `flutter run` biasa)
- [ ] Directions API aktif di Google Cloud Console
- [ ] Key Maps mengizinkan Directions API (atau "Don't restrict key")

### Duplicate-app error
- [ ] Sudah ada try-catch di main.dart dan fcm_service.dart
- [ ] Jika masih muncul, cek FirebaseInitProvider di Android native

### Peta tidak tampil
- [ ] key.properties punya MAPS_API_KEY
- [ ] build.gradle.kts baca key → manifestPlaceholders

---

## 6. File yang Diperbarui Hari Ini

| File | Perubahan |
|------|-----------|
| ios/GoogleService-Info.plist | Key iOS baru |
| ios/AppDelegate.swift | Key Maps baru |
| web/track.html | Key traka (web) baru |
| scripts/run_hybrid.ps1 | Path robust, tampilkan MAPS_API_KEY |
