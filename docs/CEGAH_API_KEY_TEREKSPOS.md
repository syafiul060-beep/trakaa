# Cegah API Key Terekspos ke Git

**Penting:** Jangan pernah commit API key asli ke repository. GitHub Secret Scanning akan mendeteksi dan mengirim alert.

---

## Setup untuk Developer Baru (Setelah Clone Repo)

Setelah clone repo, buat file config berikut (semua di `.gitignore`, tidak ikut ter-commit):

### 1. Keys.plist (iOS Maps)

**Windows (PowerShell/CMD):**
```powershell
cd d:\Traka\traka\ios\Runner
copy Keys.plist.example Keys.plist
```

**Mac/Linux:**
```bash
cd traka/ios/Runner
cp Keys.plist.example Keys.plist
```

Buka `Keys.plist`, ganti `YOUR_GOOGLE_MAPS_API_KEY` dengan Maps API key Anda.

### 2. firebase-config.js (Web track.html)

**traka/web/** (untuk track.html di Flutter web):
```powershell
# Windows
cd d:\Traka\traka\web
copy firebase-config.example.js firebase-config.js
```
```bash
# Mac/Linux
cp traka/web/firebase-config.example.js traka/web/firebase-config.js
```

**traka/hosting/** (jika pakai hosting):
```powershell
# Windows
copy traka\hosting\firebase-config.example.js traka\hosting\firebase-config.js
```

**traka-admin** (untuk deploy web admin):
```powershell
# Windows
copy traka-admin\public\firebase-config.example.js traka-admin\public\firebase-config.js
```

Edit masing-masing `firebase-config.js`, ganti `YOUR_FIREBASE_WEB_API_KEY` dengan Browser/Web API key dari Firebase Console.

### 3. Firebase config (Flutter)

```powershell
cd d:\Traka\traka
flutterfire configure
```

Perintah ini akan generate:
- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

### 4. key.properties (Android Maps)

```powershell
# Windows
cd d:\Traka\traka\android
copy key.properties.example key.properties
```
```bash
# Mac/Linux
cp traka/android/key.properties.example traka/android/key.properties
```

Edit `key.properties`, tambah baris:
```properties
MAPS_API_KEY=AIzaSy_xxx
```

### 5. traka-admin .env

```powershell
# Windows
cd d:\Traka\traka-admin
copy .env.example .env
```
```bash
# Mac/Linux
cp traka-admin/.env.example traka-admin/.env
```

Edit `.env`, isi `VITE_FIREBASE_API_KEY` dan variabel lain sesuai Firebase Console.

> **Catatan:** API key didapat dari project owner atau [Google Cloud Console](https://console.cloud.google.com/) → project syafiul-traka → Credentials.

---

## File yang JANGAN Di-commit (sudah di .gitignore)

| File | Isi |
|------|-----|
| `traka/lib/firebase_options.dart` | Firebase keys (generate via `flutterfire configure`) |
| `traka/android/key.properties` | MAPS_API_KEY |
| `traka/android/app/google-services.json` | Firebase Android config |
| `traka/ios/Runner/GoogleService-Info.plist` | Firebase iOS config |
| `traka/ios/Runner/Keys.plist` | MAPS_API_KEY untuk Maps iOS |
| `traka/hosting/firebase-config.js` | Firebase Web key |
| `traka/web/firebase-config.js` | Firebase Web key (track.html) |
| `traka-admin/.env` | VITE_FIREBASE_API_KEY, dll |
| `traka-admin/public/firebase-config.js` | Firebase Web key |

---

## Dokumen: JANGAN Tulis Key Asli

File seperti `API_KEY_REFERENSI.md`, `CEK_APLIKASI_API_KEY_APP_CHECK.md` — gunakan placeholder (`xxx`, `YOUR_KEY`) saja, bukan nilai asli.

---

## Jika Key Sudah Terekspos

1. **Rotate segera** — regenerate semua key di Google Cloud Console
2. **Update aplikasi** — ikuti `docs/ROTATE_API_KEYS_LANGKAH.md`
3. **Nonaktifkan key lama** — di Google Cloud Console → Credentials

> **Catatan:** Key yang sudah di-push ke Git history tetap bisa dilihat. Rotasi wajib.
