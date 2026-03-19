# Referensi API Key Traka (Setelah Rotasi)

Dokumen ini memetakan **semua lokasi** API key di proyek Traka. Gunakan untuk verifikasi setelah rotasi key.

---

## Daftar Key (JANGAN tulis nilai asli di sini!)

| Key | Lokasi nilai | Dipakai untuk |
|-----|--------------|---------------|
| **Browser** | firebase-config.js, .env | Firebase Web (umum) |
| **Android** | google-services.json | Firebase + Maps Android |
| **iOS** | GoogleService-Info.plist | Firebase iOS |
| **Maps** | key.properties, Keys.plist (iOS) | Directions API, Maps SDK |
| **traka (web)** | firebase-config.js | track.html |

---

## Peta Lokasi File

### 1. Flutter App (traka/)

| File | Key | Nilai yang dipakai |
|------|-----|--------------------|
| `lib/firebase_options.dart` | Browser, Android, iOS | Browser, Android, iOS (sudah benar) |
| `android/app/google-services.json` | Android | Dari Firebase Console / flutterfire configure |
| `android/key.properties` | Maps | `MAPS_API_KEY=xxx` (file di .gitignore) |
| `ios/Runner/GoogleService-Info.plist` | iOS | Dari Firebase Console / flutterfire configure |
| `ios/Runner/Keys.plist` | Maps (GMSServices) | `MAPS_API_KEY` (file di .gitignore) |
| `lib/config/maps_config.dart` | Maps | Dari `--dart-define=MAPS_API_KEY` (via run_hybrid.ps1) ✓ |

### 2. Web (traka/web/)

| File | Key | Nilai yang dipakai |
|------|-----|--------------------|
| `web/track.html` | traka (web) | Load dari `firebase-config.js` (gitignored) |

### 3. Hosting (traka/hosting/)

| File | Key | Catatan |
|------|-----|---------|
| `hosting/track.html` | - | Load dari `firebase-config.js` (user buat dari example) |
| `hosting/firebase-config.example.js` | - | Template; user copy ke `firebase-config.js` dan isi **traka (web)** key |
| `hosting/assets/index-DqQmTRws.js` | Built | **REBUILD** traka-admin dengan `.env` baru, lalu deploy ulang |

### 4. traka-admin

| File | Key | Catatan |
|------|-----|---------|
| `.env` | traka (web) | `VITE_FIREBASE_API_KEY=xxx` (JANGAN commit .env!) |
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
