# Phase 1 Hybrid: Checklist Deployment

Panduan langkah demi langkah untuk mengaktifkan **driver_status → Redis** (Phase 1).

---

## Ringkasan

| Yang berubah | Sebelum | Sesudah |
|--------------|---------|---------|
| driver_status | Firestore | Redis (via traka-api) |
| orders, users, chat | Firestore | Tetap Firestore |

**Yang dibutuhkan Phase 1:**
- Upstash Redis
- traka-api (deploy)
- Firebase Service Account (untuk auth)
- PostgreSQL **tidak wajib** (opsional untuk orders/users di fase berikutnya)

---

## Checklist

### 1. Setup Upstash Redis

- [ ] Buka [Upstash Console](https://console.upstash.com)
- [ ] Create Database → pilih region terdekat (ap-southeast-1 untuk Indonesia)
- [ ] Salin **Redis URL** (format: `redis://default:PASSWORD@HOST:PORT`)

---

### 2. Setup traka-api

- [ ] `cd traka-api && npm install`
- [ ] Buat `.env` (copy dari `.env.example`):

```env
PORT=3001
REDIS_URL=redis://default:XXXX@XXXX.upstash.io:6379

# Firebase (wajib untuk auth driver)
FIREBASE_SERVICE_ACCOUNT_JSON={"type":"service_account","project_id":"...","private_key":"...","client_email":"..."}

# PostgreSQL opsional untuk Phase 1 (bisa dikosongkan)
# DATABASE_URL=postgresql://...
```

- [ ] Download Firebase Service Account:
  1. Firebase Console → Project Settings → Service accounts
  2. Generate new private key
  3. Paste seluruh isi JSON ke variable `FIREBASE_SERVICE_ACCOUNT_JSON` (untuk Railway/Render)
  4. Atau simpan ke `firebase-service-account.json` dan set `FIREBASE_SERVICE_ACCOUNT_PATH=./firebase-service-account.json`

---

### 3. Test traka-api Lokal

```bash
cd traka-api
npm start
```

- [ ] `curl http://localhost:3001/health` → `{"ok":true,"status":"traka-api"}`
- [ ] `curl http://localhost:3001/api/driver/status` → `{"drivers":[]}`

---

### 4. Deploy traka-api (Railway / Render)

**Railway:**
- [ ] New Project → Deploy from GitHub (atau folder)
- [ ] Root: `traka-api`
- [ ] Variables: `REDIS_URL`, `FIREBASE_SERVICE_ACCOUNT_JSON` (paste JSON)
- [ ] Deploy → catat URL (satu kanonis: `PRODUCTION_API_BASE_URL.txt` — mis. `https://trakaa-production.up.railway.app`)

**Render:**
- [ ] New Web Service → connect repo
- [ ] Root: `traka-api`
- [ ] Build: `npm install`
- [ ] Start: `node src/index.js` atau `npm start`
- [ ] Env: `REDIS_URL`, `FIREBASE_SERVICE_ACCOUNT_JSON`

- [ ] Verifikasi: `curl https://YOUR-API-URL/health`

---

### 5. Build Flutter dengan Hybrid

Ganti `YOUR_API_URL` dengan URL traka-api yang di-deploy (tanpa trailing slash).

**Menggunakan script (disarankan):**
```powershell
# Windows PowerShell
cd traka
.\scripts\build_hybrid.ps1 -ApiUrl "https://YOUR_API_URL" -Target apk
```

```bash
# Linux/macOS
cd traka
./scripts/build_hybrid.sh https://YOUR_API_URL apk
```

**Manual:**
```bash
cd traka
flutter build apk --dart-define=TRAKA_API_BASE_URL=https://YOUR_API_URL --dart-define=TRAKA_USE_HYBRID=true
flutter build ios --dart-define=TRAKA_API_BASE_URL=https://YOUR_API_URL --dart-define=TRAKA_USE_HYBRID=true
```

**Debug/Development:**
```bash
flutter run --dart-define=TRAKA_API_BASE_URL=https://YOUR_API_URL --dart-define=TRAKA_USE_HYBRID=true
```

- [ ] Build berhasil
- [ ] Test: login sebagai driver → mulai kerja → cek lokasi ter-update
- [ ] Cek Redis di Upstash: key `driver_status:{uid}` muncul saat driver aktif

---

### 6. Release

- [ ] Upload APK/IPA ke Play Store / App Store
- [ ] Atau distribusi internal (Firebase App Distribution, dll.)
- [ ] Pastikan semua build production memakai `--dart-define` hybrid

---

## Rollback (jika ada masalah)

1. Build Flutter **tanpa** `TRAKA_USE_HYBRID` (atau `=false`):
   ```bash
   flutter build apk --dart-define=TRAKA_USE_HYBRID=false
   ```
2. Release versi lama → driver_status kembali ke Firestore

---

## Verifikasi Hybrid Aktif

- Driver buka app → mulai kerja → pilih rute
- Di Upstash Redis: buka Data Browser → cek key `driver_status:{driver_uid}`
- Penumpang Lacak Driver: lokasi driver ter-update (polling 4 detik)
