# Referensi API Key Traka (Setelah Rotasi)

Dokumen ini memetakan **semua lokasi** API key di proyek Traka. Gunakan untuk verifikasi setelah rotasi key.

---

## Daftar Key Saat Ini (19 Mar 2026)

| Key | Nilai | Dipakai untuk |
|-----|-------|----------------|
| **Browser** | `AIzaSyAL9LaqOBn6vjC_D9xK02Afnl68s6BkXJU` | Firebase Web (umum) |
| **Android** | `AIzaSyD7Jz7Cs4UKlOWT2Ztr7LulhlNuHV0hOlA` | Firebase + Maps Android |
| **iOS** | `AIzaSyBlirfTyEZ2nQYNRyNFPH4w4N7DHP3eip8` | Firebase iOS |
| **Maps** | `AIzaSyBhWS2y8VVrsNEikCIv13y829WYXZGBPvw` | Directions API, Maps SDK |
| **traka id.traka.app** | `AIzaSyB7Qh7jTbAb_SfVNNbEuO0XutQ0dJIZr8U` | Firebase auto (id.traka.app) |
| **traka com.example.traka** | `AIzaSyAhqTBcefGufxNRa8MFfbcpKUmNlky-m20` | Firebase auto (com.example.traka) |
| **traka (web)** | `AIzaSyCyD08AJ_j7LSciMMwmCVVz6rq-2k_C59k` | Firebase Web app |

---

## Peta Lokasi File

### 1. Flutter App (traka/)

| File | Key | Nilai yang dipakai |
|------|-----|--------------------|
| `lib/firebase_options.dart` | Browser, Android, iOS | Browser, Android, iOS (sudah benar) |
| `android/app/google-services.json` | Android | `AIzaSyD7Jz7Cs4UKlOWT2Ztr7LulhlNuHV0hOlA` ✓ |
| `android/key.properties` | Maps | `MAPS_API_KEY=AIzaSyBhWS2y8VVrsNEikCIv13y829WYXZGBPvw` ✓ |
| `ios/Runner/GoogleService-Info.plist` | iOS | `AIzaSyBlirfTyEZ2nQYNRyNFPH4w4N7DHP3eip8` ✓ |
| `ios/Runner/AppDelegate.swift` | Maps (GMSServices) | `AIzaSyBhWS2y8VVrsNEikCIv13y829WYXZGBPvw` ✓ |
| `lib/config/maps_config.dart` | Maps | Dari `--dart-define=MAPS_API_KEY` (via run_hybrid.ps1) ✓ |

### 2. Web (traka/web/)

| File | Key | Nilai yang dipakai |
|------|-----|--------------------|
| `web/track.html` | traka (web) | `AIzaSyCyD08AJ_j7LSciMMwmCVVz6rq-2k_C59k` ✓ |

### 3. Hosting (traka/hosting/)

| File | Key | Catatan |
|------|-----|---------|
| `hosting/track.html` | - | Load dari `firebase-config.js` (user buat dari example) |
| `hosting/firebase-config.example.js` | - | Template; user copy ke `firebase-config.js` dan isi **traka (web)** key |
| `hosting/assets/index-DqQmTRws.js` | Built | **REBUILD** traka-admin dengan `.env` baru, lalu deploy ulang |

### 4. traka-admin

| File | Key | Catatan |
|------|-----|---------|
| `.env` | traka (web) | `VITE_FIREBASE_API_KEY=AIzaSyCyD08AJ_j7LSciMMwmCVVz6rq-2k_C59k` |
| `public/firebase-config.js` | traka (web) | Copy dari example, isi apiKey |

**Langkah:** Set `VITE_FIREBASE_API_KEY` di `.env`, lalu `npm run build`. Deploy hasil build ke hosting.

### 5. Android Manifest

| Sumber | Key |
|--------|-----|
| `android/app/build.gradle.kts` | Baca `MAPS_API_KEY` dari `key.properties` → `manifestPlaceholders["mapsApiKey"]` |
| `AndroidManifest.xml` | `${mapsApiKey}` → Maps SDK |

---

## Checklist Verifikasi

- [x] `firebase_options.dart` — Browser, Android, iOS
- [x] `google-services.json` — Android
- [x] `key.properties` — MAPS_API_KEY (Maps)
- [x] `GoogleService-Info.plist` — iOS
- [x] `AppDelegate.swift` — Maps (GMSServices)
- [x] `web/track.html` — traka (web)
- [ ] `traka-admin/.env` — VITE_FIREBASE_API_KEY (manual)
- [ ] `hosting/firebase-config.js` — apiKey (manual, dari example)
- [ ] `hosting/assets/*` — Rebuild traka-admin + deploy

---

## Perintah Run yang Benar

```powershell
cd d:\Traka\traka
.\scripts\run_hybrid.ps1
```

Script akan membaca `MAPS_API_KEY` dari `android/key.properties` dan meneruskannya ke Flutter.
