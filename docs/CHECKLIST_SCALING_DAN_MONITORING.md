# Checklist Scaling & Monitoring – Traka (1–5 Juta Pengguna)

Dokumen ini berisi checklist konkret per file/endpoint dan draft konfigurasi untuk scaling serta monitoring.

---

## 1. Checklist per File

### traka-api

| File | Tindakan | Prioritas | Status |
|------|----------|-----------|--------|
| `src/index.js` | Ganti rate limit in-memory → Redis store | 🔴 Tinggi | [x] |
| `src/index.js` | Tambah clustering (PM2 atau Node cluster) | 🔴 Tinggi | [x] |
| `src/lib/redis.js` | Tambah connection pool / retry logic | 🟡 Sedang | [x] |
| `src/lib/pg.js` | Konfigurasi pool (max, min, idleTimeoutMillis) | 🔴 Tinggi | [x] |
| `src/routes/driver.js` | Optimasi `GET /status` – ganti full SCAN | 🔴 Tinggi | [x] |
| `src/routes/driver.js` | Tambah pagination / filter region | 🟡 Sedang | [x] |
| `src/routes/orders.js` | Tambah LIMIT pada query list | 🟡 Sedang | [x] |
| `src/routes/orders.js` | Tambah index di PostgreSQL untuk `driverUid`, `passengerUid`, `updatedAt` | 🟡 Sedang | [ ] |

### traka/functions

| File | Tindakan | Prioritas | Status |
|------|----------|-----------|--------|
| `functions/index.js` | Set `minInstances` untuk callable kritis | 🔴 Tinggi | [x] |
| `functions/index.js` | Tambah `memory` / `timeout` jika perlu | 🟡 Sedang | [ ] |

### traka

| File | Tindakan | Prioritas | Status |
|------|----------|-----------|--------|
| `firebase.json` | Pastikan functions runtime Node 20+ | 🟢 Rendah | [ ] |

---

## 2. Checklist per Endpoint

| Endpoint | Masalah | Solusi | Status |
|----------|---------|--------|--------|
| `GET /api/driver/status` | Full SCAN Redis O(n), lambat saat banyak driver | Gunakan Geo/Sorted Set atau pagination + filter region | [x] |
| `GET /api/driver/:uid/status` | OK – lookup O(1) | - | ✅ |
| `POST /api/driver/location` | OK | - | ✅ |
| `DELETE /api/driver/status` | OK | - | ✅ |
| `GET /api/orders` | Query tanpa LIMIT | Tambah `LIMIT 50` default, pagination | [x] |
| `GET /api/orders/:id` | OK | - | ✅ |
| `GET /api/users/:uid` | OK | - | ✅ |
| `GET /health` | Tidak cek Redis/PG | Tambah dependency check (opsional) | [x] |

---

## 3. Draft Konfigurasi Scaling

### 3.1 PostgreSQL Pool (`traka-api/src/lib/pg.js`)

```javascript
// Ganti:
pool = new Pool({ connectionString: url });

// Dengan:
pool = new Pool({
  connectionString: url,
  max: 20,                    // max connections per instance
  min: 2,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});
```

### 3.2 Redis Connection (`traka-api/src/lib/redis.js`)

```javascript
// Tambah retry strategy:
client = redis.createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379',
  socket: {
    reconnectStrategy: (retries) => {
      if (retries > 10) return new Error('Redis max retries');
      return Math.min(retries * 100, 3000);
    },
  },
});
```

### 3.3 Rate Limit dengan Redis (`traka-api`)

**Install:**
```bash
npm install rate-limit-redis
```

**Perubahan di `src/index.js`:** Pindahkan `app.use(limiter)` ke dalam `start()` setelah `initRedis()`, karena RedisStore butuh client yang sudah connect.

```javascript
const { RedisStore } = require('rate-limit-redis');
const { getRedis } = require('./lib/redis.js');

// Di dalam start(), setelah await initRedis():
const redis = getRedis();
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 100,
  message: { error: 'Terlalu banyak permintaan. Coba lagi nanti.' },
  standardHeaders: true,
  legacyHeaders: false,
  store: redis ? new RedisStore({
    sendCommand: (...args) => redis.sendCommand(args),
  }) : undefined,  // fallback ke MemoryStore jika Redis tidak ada
});
app.use(limiter);
```

### 3.4 PM2 untuk Clustering (`traka-api`)

**Install:**
```bash
npm install -g pm2
```

**Buat `traka-api/ecosystem.config.cjs`:**
```javascript
module.exports = {
  apps: [{
    name: 'traka-api',
    script: 'src/index.js',
    instances: 'max',  // atau angka: 4
    exec_mode: 'cluster',
    env: { NODE_ENV: 'production' },
    max_memory_restart: '500M',
  }],
};
```

**Jalankan:**
```bash
pm2 start ecosystem.config.cjs
```

### 3.5 Cloud Functions – minInstances (`traka/functions/index.js`)

Untuk callable yang sering dipanggil (misal `sendVerificationCode`, `loginWithOtp`):

```javascript
// Contoh: keep 1 instance warm untuk mengurangi cold start
const callable = functions
  .runWith({
    enforceAppCheck: true,
    minInstances: 1,   // untuk fungsi paling sering dipanggil
    memory: '256MB',
    timeoutSeconds: 60,
  })
  .https;
```

**Fungsi yang disarankan set minInstances:**
- `sendVerificationCode` – auth flow
- `loginWithOtp` – login
- `createOrder` – jika traffic tinggi

---

## 4. Draft Konfigurasi Monitoring

### 4.1 Health Check Extended (`traka-api/src/index.js`)

```javascript
app.get('/health', async (req, res) => {
  const checks = { api: true, redis: false, pg: false };
  try {
    const redis = getRedis();
    if (redis) {
      await redis.ping();
      checks.redis = true;
    }
  } catch (_) {}
  try {
    const pg = getPg();
    if (pg) {
      await pg.query('SELECT 1');
      checks.pg = true;
    }
  } catch (_) {}
  const ok = checks.api && checks.redis;
  res.status(ok ? 200 : 503).json({ ok, status: 'traka-api', checks });
});
```

### 4.2 Structured Logging (Winston – opsional)

**Install:**
```bash
npm install winston
```

**Buat `traka-api/src/lib/logger.js`:**
```javascript
const winston = require('winston');

module.exports = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  defaultMeta: { service: 'traka-api' },
  transports: [
    new winston.transports.Console(),
    // new winston.transports.File({ filename: 'logs/error.log', level: 'error' }),
  ],
});
```

### 4.3 Firebase Performance Monitoring (Mobile)

Di Flutter app, pastikan Firebase Performance sudah di-init:

```dart
// Di main.dart
await FirebasePerformance.instance.setPerformanceCollectionEnabled(true);
```

### 4.4 Sentry (Error Tracking)

**traka-api:**
```bash
npm install @sentry/node
```

**Di `src/index.js` (paling atas):**
```javascript
const Sentry = require('@sentry/node');

if (process.env.SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: process.env.NODE_ENV || 'development',
    tracesSampleRate: 0.1,
  });
  app.use(Sentry.Handlers.requestHandler());
  app.use(Sentry.Handlers.errorHandler());
}
```

### 4.5 Metrik yang Disarankan

| Metrik | Sumber | Tindakan |
|--------|--------|----------|
| Request latency (p50, p95, p99) | APM / Load balancer | Alert jika p95 > 2s |
| Error rate | Sentry / logs | Alert jika > 1% |
| Redis memory / connections | Upstash dashboard / Redis INFO | Monitor kuota |
| PostgreSQL connections | `pg_stat_activity` | Alert jika mendekati max |
| Cloud Functions cold start | Firebase Console | Monitor, tambah minInstances jika perlu |
| Rate limit hits | Custom metric | Log saat user kena limit |

---

## 5. Optimasi Driver Status (Alternatif SCAN)

### Opsi A: Geo Hash + Sorted Set (Redis)

Simpan driver per region saat update location:

```javascript
// Saat POST /location – tambah ke sorted set per region
const geohash = require('ngeohash'); // npm install ngeohash
const precision = 5; // ~5km
const hash = geohash.encode(latitude, longitude, precision);
await redis.zAdd(`drivers:region:${hash}`, { score: Date.now(), value: uid });
await redis.setEx(KEY_PREFIX + uid, TTL_SECONDS, JSON.stringify(data));
```

Query by region:
```javascript
// GET /status?lat=...&lng=...&radius=50
// Ambil geohash neighbors, ZRANGE per region, lalu GET per uid
```

### Opsi B: Pagination Sederhana

```javascript
// GET /api/driver/status?cursor=0&limit=50
// SCAN dengan cursor, return max 50, next cursor
```

---

## 6. Ringkasan Prioritas

| # | Item | Effort | Impact |
|---|------|--------|--------|
| 1 | Rate limit Redis store | Sedang | Tinggi |
| 2 | PG pool config | Rendah | Tinggi |
| 3 | Optimasi GET /driver/status | Tinggi | Tinggi |
| 4 | PM2 clustering | Rendah | Tinggi |
| 5 | Cloud Functions minInstances | Rendah | Sedang |
| 6 | Health check extended | Rendah | Sedang |
| 7 | Sentry / error tracking | Sedang | Sedang |
| 8 | Orders pagination | Rendah | Sedang |

---

## 7. Referensi

- `traka-api/docs/API.md` – Daftar endpoint
- `traka/docs/AUDIT_KESIAPAN_PRODUKSI_INDONESIA.md` – Audit keamanan
- `traka/docs/MIGRATION_HYBRID.md` – Arsitektur hybrid
- `traka-api/SETUP_REDIS.md` – Setup Redis
