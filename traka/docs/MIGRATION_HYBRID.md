# Migrasi Hybrid Traka: Firebase → Redis + PostgreSQL

Panduan langkah demi langkah untuk migrasi `driver_status` ke Redis dan data `users`/`orders` ke PostgreSQL, guna mengurangi biaya Firebase.

---

## Ringkasan

| Komponen | Sebelum | Sesudah |
|----------|---------|---------|
| driver_status | Firestore (real-time) | Redis (API) |
| users | Firestore | PostgreSQL (opsional) |
| orders | Firestore | PostgreSQL (opsional) |

**driver_status** adalah prioritas utama karena update lokasi driver sangat sering (setiap 2–15 menit per driver).

---

## Prasyarat

- Akun [Upstash](https://upstash.com) (Redis)
- Akun [Supabase](https://supabase.com) (PostgreSQL)
- Akun [Railway](https://railway.app) / [Render](https://render.com) / VPS untuk deploy backend
- Akses Firebase Console (download service account)

---

## Langkah 1: Setup Upstash Redis

1. Buka [Upstash Console](https://console.upstash.com)
2. Klik **Create Database**
3. Pilih region terdekat (mis. `ap-southeast-1` untuk Singapore)
4. Buat database, lalu salin **Redis URL** (format: `redis://default:PASSWORD@HOST:PORT`)
5. Simpan URL untuk `.env` backend

---

## Langkah 2: Setup Supabase PostgreSQL

1. Buka [Supabase Dashboard](https://supabase.com/dashboard)
2. Buat project baru (atau gunakan yang ada)
3. Di **Project Settings → Database**, salin **Connection string** (URI)
4. Format: `postgresql://postgres.[project-ref]:[PASSWORD]@aws-0-[region].pooler.supabase.com:6543/postgres`
5. Simpan untuk `.env` backend

---

## Langkah 3: Deploy Backend API

### 3.1 Persiapan lokal

```bash
cd traka-api
npm install
```

### 3.2 File `.env`

Buat file `.env` di `traka-api/` (copy dari `.env.example`):

```env
PORT=3001
REDIS_URL=redis://default:XXXX@XXXX.upstash.io:6379
DATABASE_URL=postgresql://postgres.xxx:xxx@aws-0-ap-southeast-1.pooler.supabase.com:6543/postgres
FIREBASE_SERVICE_ACCOUNT_PATH=./firebase-service-account.json
```

### 3.3 Download Firebase Service Account

1. Firebase Console → **Project Settings** (ikon gear)
2. Tab **Service accounts**
3. Klik **Generate new private key**
4. Simpan file JSON ke `traka-api/firebase-service-account.json`
5. **Jangan commit** file ini ke Git (tambah ke `.gitignore`)

### 3.4 Jalankan schema PostgreSQL

1. Buka Supabase → **SQL Editor**
2. Buka file `traka-api/scripts/schema.sql`
3. Copy seluruh isi, paste ke SQL Editor, jalankan

### 3.5 Deploy ke Railway (contoh)

1. Buat project baru di [Railway](https://railway.app)
2. **New → GitHub Repo** (atau Deploy from folder)
3. Root directory: `traka-api`
4. Tambah **Variables**:
   - `REDIS_URL`
   - `DATABASE_URL`
   - `FIREBASE_SERVICE_ACCOUNT_PATH` = `./firebase-service-account.json`
5. Untuk service account: upload file JSON sebagai **Secret** atau paste isi JSON ke variable `FIREBASE_SERVICE_ACCOUNT` (jika backend mendukung env JSON)
6. **Deploy**
7. Catat URL public (mis. `https://trakaa-production.up.railway.app`)

> **Catatan:** Railway/Render biasanya tidak punya filesystem untuk upload file. Alternatif: encode JSON sebagai base64 dan decode di startup, atau gunakan variable `GOOGLE_APPLICATION_CREDENTIALS_JSON` berisi string JSON.

### 3.6 (Opsional) Support service account dari env

Jika platform tidak mendukung file upload, ubah `traka-api/src/lib/auth.js`:

```javascript
// Cek env dulu
const json = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
if (json) {
  const serviceAccount = JSON.parse(json);
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
} else {
  // fallback ke file
  const p = process.env.FIREBASE_SERVICE_ACCOUNT_PATH || path.join(process.cwd(), 'firebase-service-account.json');
  if (fs.existsSync(p)) {
    const serviceAccount = require(p);
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  }
}
```

Lalu set variable `FIREBASE_SERVICE_ACCOUNT_JSON` = isi file JSON (paste seluruh isi).

---

## Langkah 4: Migrasi Data Firestore → PostgreSQL (opsional)

Jika ingin memindahkan `users` dan `orders` ke PostgreSQL:

1. Pastikan `schema.sql` sudah dijalankan
2. Set `FIREBASE_SERVICE_ACCOUNT_PATH` dan `DATABASE_URL` di `.env`
3. Jalankan:

```bash
cd traka-api
node scripts/migrate-firestore-to-pg.js
```

4. Cek tabel `users` dan `orders` di Supabase Table Editor

---

## Langkah 5: Konfigurasi Flutter

### 5.1 Build dengan environment

Untuk **development** (uji hybrid):

```bash
cd traka
flutter run --dart-define=TRAKA_API_BASE_URL=https://trakaa-production.up.railway.app --dart-define=TRAKA_USE_HYBRID=true
```

Untuk **production** (release):

```bash
flutter build apk --dart-define=TRAKA_API_BASE_URL=https://trakaa-production.up.railway.app --dart-define=TRAKA_USE_HYBRID=true
```

### 5.2 Tanpa dart-define (hardcode sementara)

Edit `traka/lib/config/traka_api_config.dart`:

```dart
static const String apiBaseUrl = 'https://trakaa-production.up.railway.app';
static const bool useHybrid = true;  // ubah ke true untuk aktifkan
```

> **Peringatan:** Jangan commit `useHybrid = true` ke production sebelum uji selesai.

---

## Langkah 6: Testing

### 6.1 Backend

```bash
# Health check
curl https://trakaa-production.up.railway.app/health

# Daftar driver (harus kosong awalnya)
curl https://trakaa-production.up.railway.app/api/driver/status
```

### 6.2 Flutter (driver)

1. Login sebagai driver
2. Mulai kerja (pilih rute)
3. Pastikan lokasi ter-update (cek di API: `GET /api/driver/status`)
4. Selesai kerja → status terhapus

### 6.3 Flutter (penumpang)

1. Login sebagai penumpang
2. Cari travel → driver muncul di map
3. Lacak Driver / Lacak Barang → posisi driver ter-update (polling 4 detik)

---

## Langkah 7: Rollback

Jika terjadi masalah:

1. **Flutter:** Set `TRAKA_USE_HYBRID=false` atau `useHybrid = false`
2. Rebuild dan deploy
3. Driver_status kembali ke Firestore

---

## Endpoint API

| Method | Path | Auth | Keterangan |
|--------|------|------|------------|
| GET | /health | - | Health check |
| POST | /api/driver/location | Bearer | Update lokasi driver |
| GET | /api/driver/status | - | Daftar semua driver aktif |
| GET | /api/driver/:uid/status | - | Status driver tunggal |
| DELETE | /api/driver/status | Bearer | Hapus status driver |
| GET | /api/orders | Bearer | Daftar order (jika pakai PG) |
| GET | /api/orders/:id | Bearer | Detail order |
| GET | /api/users/:uid | Bearer | Data user |

---

## Perubahan Manual yang Mungkin Diperlukan

1. **Railway/Render:** Jika service account tidak bisa di-upload sebagai file, gunakan `FIREBASE_SERVICE_ACCOUNT_JSON` (lihat Langkah 3.6).
2. **Upstash TLS:** Beberapa provider memakai `rediss://` (dengan TLS). Pastikan `REDIS_URL` sesuai.
3. **CORS:** Jika Flutter web, pastikan backend mengizinkan origin yang dipakai.
4. **currentPassengerCount:** Saat hybrid, partial update `currentPassengerCount` tidak dikirim ke API. Nilai akan ter-update saat driver mengirim lokasi berikutnya.

---

## File yang Diubah

| File | Perubahan |
|------|-----------|
| `traka/lib/config/traka_api_config.dart` | Baru – config base URL & flag hybrid |
| `traka/lib/services/traka_api_service.dart` | Baru – HTTP client API |
| `traka/lib/services/driver_status_service.dart` | Dual-write: Firestore atau API |
| `traka/lib/services/active_drivers_service.dart` | Baca dari Firestore atau API |
| `traka/lib/widgets/passenger_track_map_widget.dart` | Stream dari DriverStatusService |
| `traka/lib/screens/penumpang_screen.dart` | Stream dari DriverStatusService |
| `traka-api/src/routes/driver.js` | GET /status untuk daftar driver |
| `traka-api/src/index.js` | Init Firebase |
| `traka-api/scripts/migrate-firestore-to-pg.js` | Baru – script migrasi |
| `traka-admin/src/config/apiConfig.js` | Baru – config API hybrid |
| `traka-admin/src/services/trakaApi.js` | Baru – fetch driver status dari API |
| `traka-admin/src/pages/Drivers.jsx` | Baca driver_status dari API jika hybrid |
| `traka-admin/src/pages/Dashboard.jsx` | Hitung Driver Aktif dari API jika hybrid |
| `traka-admin/src/pages/Users.jsx` | Lokasi driver dari API jika hybrid |

---

## Web Admin (traka-admin)

Agar sinkron dengan hybrid, set di `.env`:

```env
VITE_TRAKA_API_BASE_URL=https://trakaa-production.up.railway.app
VITE_TRAKA_USE_HYBRID=true
```

Lalu rebuild: `npm run build`
