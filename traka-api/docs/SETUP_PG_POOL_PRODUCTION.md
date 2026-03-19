# PG_POOL_MAX untuk Produksi

## Penggunaan di Traka

- **PostgreSQL pool:** Connection pool untuk endpoint `/api/orders` dan `/api/users`
- **Default:** 50 (jika `PG_POOL_MAX` tidak diset)
- **Rekomendasi:** 50–100 untuk traffic 1–5 juta pengguna

## Set PG_POOL_MAX di Produksi

| Platform | Status |
|----------|--------|
| Railway | ✓ Sudah (cukup untuk produksi Traka) |
| Render / Vercel / PM2 / Docker | Opsional — hanya jika dipakai |

### Railway / Render / Vercel / sejenisnya

1. Buka project → **Variables** / **Environment**
2. Tambah variable: `PG_POOL_MAX = 50` atau `100`
3. Redeploy aplikasi

### PM2 / VPS

Di `.env`:

```
PG_POOL_MAX=50
```

Restart:

```bash
pm2 restart traka-api --update-env
```

### Docker

Di `docker-compose.yml` atau `docker run`:

```yaml
environment:
  - PG_POOL_MAX=50
```

Atau `docker run`:

```bash
docker run -e PG_POOL_MAX=50 ...
```

## Referensi

- `traka-api/src/lib/pg.js` – implementasi pool
- `traka-api/.env.example` – contoh env vars
- `docs/CHECKLIST_SCALING_DAN_MONITORING.md` – konfigurasi scaling
