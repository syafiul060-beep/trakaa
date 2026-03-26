# traka-api

Backend Node (Express): Redis untuk status driver / matching, PostgreSQL untuk order (opsional). Lihat [`docs/API.md`](docs/API.md) dan [`.env.example`](.env.example).

## Checklist produksi (cepat)

**Push `main` →** Railway **Redeploy** (atau tunggu auto-deploy) → **`GET /health`** sukses → pastikan **`REDIS_URL`**, kredensial **Firebase**, dan **`ALLOWED_ORIGINS`** → jika load test lokasi driver padat, set **`DRIVER_LOCATION_RATE_LIMIT_PER_MIN`** (default 120/menit per UID). Rincian: [`docs/RAILWAY_DEPLOY_CEPAT.md`](docs/RAILWAY_DEPLOY_CEPAT.md); health & alert: [`docs/MONITORING_PRODUCTION.md`](docs/MONITORING_PRODUCTION.md).

## Lokal

```bash
cp .env.example .env
npm install
npm run dev
```
