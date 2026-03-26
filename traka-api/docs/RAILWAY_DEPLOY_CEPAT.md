# Deploy cepat traka-api (Railway)

## Agar kode terbaru jalan di production

1. **Pastikan** commit sudah di `main` (GitHub).
2. Di [Railway](https://railway.app) → proyek **traka-api** (contoh: **virtuous-respect**) → service API Node.
3. **Deploy:**
   - Jika terhubung GitHub: biasanya **auto-deploy** setelah push; atau tab **Deployments** → **Redeploy** pada deploy terakhir.
   - Secara manual: **Settings** → tied branch `main` → trigger deploy.
4. **Verifikasi:** `GET https://<URL-API-ANDA>/health` → `200`, `checks.redis: true` (jika Redis wajib untuk Anda).
5. **Opsional:** set env `APP_VERSION` (mis. `1.2.3`); nilai muncul di JSON `/health` untuk memastikan instance yang jalan.

## Variabel penting (Variables)

| Variabel | Catatan |
|----------|---------|
| `REDIS_URL` | Wajib untuk driver status + rate limit terdistribusi. |
| `FIREBASE_SERVICE_ACCOUNT_JSON` atau `FIREBASE_SERVICE_ACCOUNT_PATH` | Wajib untuk `verifyToken`. |
| `ALLOWED_ORIGINS` | Produksi: daftar origin admin/app, **bukan** `*`. |
| `DRIVER_LOCATION_RATE_LIMIT_PER_MIN` | **Opsional.** Default **120** request/menit per **UID** pada `POST /api/driver/location`. Naikkan (mis. `300`) hanya saat **load test** massal; turunkan lagi setelah uji. |
| `DATABASE_URL` | Jika fitur order PG dipakai. |

Setelah mengubah Variables, Railway biasanya **me-redeploy** otomatis; jika tidak, **Redeploy** manual.

## Rate limit lokasi driver (429)

Jika banyak akun driver uji mengirim lokasi sangat sering → respons **429** `Update lokasi terlalu sering` adalah **pembatasan sengaja**. Solusi: naikkan `DRIVER_LOCATION_RATE_LIMIT_PER_MIN` di Railway, atau kurangi frekuensi klien uji.

## Rujukan

- [`API.md`](API.md) — endpoint termasuk driver & 429.
- [`MONITORING_PRODUCTION.md`](MONITORING_PRODUCTION.md) — health & monitoring.
- [`SETUP_REDIS_PRODUCTION.md`](SETUP_REDIS_PRODUCTION.md) — Redis.
