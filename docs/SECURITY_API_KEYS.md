# Keamanan API Keys

GitHub mendeteksi API keys yang ter-expose di repository. Ikuti langkah ini:

## 1. Rotate (Ganti) Semua API Keys yang Ter-expose

### Firebase / Google Cloud Console
1. Buka [Google Cloud Console](https://console.cloud.google.com/) → API & Services → Credentials
2. Untuk setiap API key yang ter-expose, buat key baru
3. Nonaktifkan/hapus key lama

### Google Maps API
- Buka Cloud Console → Credentials → API Keys
- Restrict key (HTTP referrers, Android/iOS app restrictions)
- Buat key baru jika perlu

## 2. Setup Lokal Setelah Perubahan

### traka (Flutter)
```bash
cd traka
flutterfire configure   # Generate lib/firebase_options.dart (file ini di .gitignore)
flutter build apk --dart-define=MAPS_API_KEY=YOUR_NEW_MAPS_KEY
```

### traka-admin
```bash
cd traka-admin
cp public/firebase-config.example.js public/firebase-config.js
# Edit firebase-config.js, isi API key dari Firebase Console
```

### traka_admin
Buat `.env` dengan:
```
VITE_FIREBASE_API_KEY=xxx
VITE_FIREBASE_AUTH_DOMAIN=xxx
...
```

### track.html (traka-admin & traka/hosting)
Copy `firebase-config.example.js` ke `firebase-config.js`, isi API key.

## 3. Jangan Commit
- `lib/firebase_options.dart` (traka)
- `firebase-config.js` (traka-admin, traka/hosting)
- `.env` (semua project)
