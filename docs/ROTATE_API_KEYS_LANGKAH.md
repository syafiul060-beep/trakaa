# Panduan Rotate API Keys - Sesuai Aplikasi Traka

## Jenis API yang Dibutuhkan (Google Cloud Console)

Aktifkan API berikut di [Google Cloud Console](https://console.cloud.google.com/) → **APIs & Services** → **Library**:

| API | Dipakai untuk |
|-----|---------------|
| **Maps SDK for Android** | Peta di aplikasi Flutter Android |
| **Maps SDK for iOS** | Peta di aplikasi Flutter iOS |
| **Directions API** | Rute perjalanan (polyline, jarak, ETA) |
| **Routes API** | Estimasi biaya tol |
| **Geocoding API** | Alamat ↔ koordinat (alamat ke lat/lng, reverse geocode) |
| **Firebase** | Auth, Firestore, Storage, Functions, dll (otomatis via Firebase project) |

> **Catatan:** Firebase (Auth, Firestore, dll) dikelola lewat Firebase Console. API key untuk Firebase biasanya sudah terhubung ke project.

---

## Ringkasan: 4 Key yang Perlu Di-regenerate

| # | Key di Google Cloud | Dipakai di |
|---|---------------------|------------|
| 1 | **Browser key** (Firebase Web) | traka-admin, traka_admin, track.html |
| 2 | **Android key** (Firebase) | Aplikasi Flutter Android |
| 3 | **iOS key** (Firebase) | Aplikasi Flutter iOS |
| 4 | **Android key** (Maps) | Google Maps di Flutter |

> **Catatan:** Key #2 dan #4 bisa jadi **satu key yang sama** jika Maps & Firebase Android memakai key yang sama. Cek di Credentials — jika ada 2 "Android key", satu untuk Firebase, satu untuk Maps.

---

## LANGKAH 1: Regenerate Key di Google Cloud Console

1. Buka [console.cloud.google.com](https://console.cloud.google.com/)
2. Pilih project **syafiul-traka**
3. Menu **APIs & Services** → **Credentials**

### Untuk setiap key yang ter-expose:

- Klik nama key → **Regenerate key** (atau **Edit** → **Regenerate**)
- **SALIN** key baru dan simpan sementara (Notepad)
- Key lama otomatis tidak valid setelah regenerate

### Urutan regenerate (disarankan):

1. **Browser key** (Firebase Web) → simpan sebagai **KEY_WEB**
2. **Android key** (Firebase) → simpan sebagai **KEY_ANDROID**
3. **iOS key** (Firebase) → simpan sebagai **KEY_IOS**
4. **Android key** (Maps) → simpan sebagai **KEY_MAPS**

---

## LANGKAH 2: Update Aplikasi dengan Key Baru

### 2.1 traka-admin (Web + track.html)

**File:** `traka-admin/public/firebase-config.js`

```bash
cd traka-admin
copy public\firebase-config.example.js public\firebase-config.js
```

Edit `public/firebase-config.js`, isi **KEY_WEB**:

```javascript
window.FIREBASE_CONFIG = {
  apiKey: "KEY_WEB_BARU_ANDA",
  projectId: "syafiul-traka",
  authDomain: "syafiul-traka.firebaseapp.com",
  storageBucket: "syafiul-traka.firebasestorage.app"
};
```

**File:** `traka-admin/.env` (untuk build Vite)

```
VITE_FIREBASE_API_KEY=KEY_WEB_BARU_ANDA
VITE_FIREBASE_AUTH_DOMAIN=syafiul-traka.firebaseapp.com
VITE_FIREBASE_PROJECT_ID=syafiul-traka
VITE_FIREBASE_STORAGE_BUCKET=syafiul-traka.firebasestorage.app
VITE_FIREBASE_MESSAGING_SENDER_ID=652861002574
VITE_FIREBASE_APP_ID=1:652861002574:web:4bdc74993fc9859650041f
```

---

### 2.2 traka_admin (Web)

**File:** `traka_admin/.env`

```
VITE_FIREBASE_API_KEY=KEY_WEB_BARU_ANDA
VITE_FIREBASE_AUTH_DOMAIN=syafiul-traka.firebaseapp.com
VITE_FIREBASE_PROJECT_ID=syafiul-traka
VITE_FIREBASE_STORAGE_BUCKET=syafiul-traka.firebasestorage.app
VITE_FIREBASE_MESSAGING_SENDER_ID=652861002574
VITE_FIREBASE_APP_ID=1:652861002574:web:4bdc74993fc9859650041f
```

---

### 2.3 track.html (traka/hosting)

**File:** `traka/hosting/firebase-config.js`

```bash
cd traka/hosting
copy firebase-config.example.js firebase-config.js
```

Edit `firebase-config.js`, isi **KEY_WEB** (sama dengan traka-admin).

---

### 2.4 traka (Flutter) — Android + iOS + Maps

**Cara termudah:** Jalankan FlutterFire untuk generate config Firebase:

```bash
cd traka
flutterfire configure
```

Perintah ini akan:
- Generate `lib/firebase_options.dart` dengan **KEY_ANDROID** dan **KEY_IOS** baru
- Update `android/app/google-services.json` jika perlu

**Untuk Maps API key** — edit `traka/android/key.properties`:

```properties
# Tambah baris ini (ganti dengan KEY_MAPS)
MAPS_API_KEY=KEY_MAPS_BARU_ANDA
```

Jika `key.properties` belum ada, copy dari example:

```bash
copy traka\android\key.properties.example traka\android\key.properties
```

Lalu edit, tambah `MAPS_API_KEY=KEY_MAPS_BARU_ANDA`.

**Untuk iOS Maps** — edit `traka/ios/Runner/Keys.plist` (atau copy dari `Keys.plist.example`):

```xml
<key>MAPS_API_KEY</key>
<string>KEY_MAPS_BARU_ANDA</string>
```

**Build APK:**

```bash
cd traka
flutter build apk
```

Key Maps diambil dari `key.properties` (MAPS_API_KEY) atau env `MAPS_API_KEY`.

**Build App Bundle (Play Store):**

```bash
flutter build appbundle
```

---

## LANGKAH 3: Nonaktifkan Key Lama

Setelah aplikasi berjalan normal dengan key baru:

1. Buka Google Cloud Console → Credentials
2. Untuk setiap key lama yang sudah tidak dipakai → **Disable** atau **Delete**

---

## Checklist Singkat

- [ ] Regenerate Browser key → KEY_WEB
- [ ] Regenerate Android key (Firebase) → KEY_ANDROID
- [ ] Regenerate iOS key → KEY_IOS
- [ ] Regenerate Android key (Maps) → KEY_MAPS
- [ ] traka-admin: firebase-config.js + .env
- [ ] traka_admin: .env
- [ ] traka/hosting: firebase-config.js
- [ ] traka: flutterfire configure + key.properties (MAPS_API_KEY)
- [ ] Tes: traka-admin login, track.html, Flutter app
- [ ] Nonaktifkan key lama
