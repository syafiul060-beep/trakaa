# Railway Deployment – Troubleshooting

## Build Failed / Crashed

### 1. Root Directory (Paling Sering)

Railway harus build dari folder `traka-api`. Jika repo Anda monorepo (traka, traka-admin, traka-api dalam satu repo):

1. Buka Railway → project **virtuous-respect** → service **trakaa**
2. **Settings** → **Source**
3. **Root Directory:** isi `traka-api`
4. **Redeploy**

![Root Directory](https://docs.railway.app/guides/monorepo#root-directory)

---

### 2. Environment Variables Wajib

Pastikan semua variable ini ada di Railway Variables:

| Variable | Wajib | Contoh |
|----------|-------|--------|
| REDIS_URL | ✓ | `rediss://default:TOKEN@xxx.upstash.io:6379` |
| FIREBASE_SERVICE_ACCOUNT_JSON | ✓ | `{"type":"service_account",...}` |
| ALLOWED_ORIGINS | ✓ | `https://app.traka.id,https://admin.traka.id` |
| DATABASE_URL | Jika pakai orders | `postgresql://...` |
| PG_POOL_MAX | Opsional | `50` |

Jika **REDIS_URL** salah atau Redis tidak bisa diakses, app akan crash saat startup.

---

### 3. Cek Build Logs

1. Railway → Deployments → klik deployment yang failed
2. Tab **Build Logs** – cek error saat `npm install` atau build
3. Tab **Deploy Logs** – cek error saat app start (mis. Redis connection failed)

---

### 4. Runtime Crash

Jika build sukses tapi app crash setelah start:

- **Redis connection failed** → cek REDIS_URL (pakai `rediss://` untuk TLS)
- **Firebase init error** → cek FIREBASE_SERVICE_ACCOUNT_JSON (harus valid JSON satu baris)
- **Port** → Railway set PORT otomatis, jangan override

---

### 5. Repo Terpisah (trakaa)

Jika service **trakaa** terhubung ke repo terpisah (bukan monorepo Traka):

- Root Directory bisa kosong atau `.`
- Pastikan `package.json` dan `src/` ada di root repo
