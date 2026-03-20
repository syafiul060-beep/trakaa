# Monitoring production — traka-api (**poin 3**)

Checklist operasional **Tahap 1** (APP_VERSION, Sentry, uptime, QA): [`TAHAPAN_1_OBSERVABILITAS.md`](TAHAPAN_1_OBSERVABILITAS.md).

## Yang sudah ada

- **Sentry** — `instrument.js`, error handler Express (set `SENTRY_DSN`).
- **`GET /health`** — `ok`, `checks.redis`, `checks.pg`, `uptimeSeconds`, opsional `version` dari env `APP_VERSION`.

## Yang disarankan di server

1. **Uptime / synthetic check** — ping `GET /health` tiap 1–5 menit dari UptimeRobot, Better Stack, atau load balancer. Alert jika non-200 atau `ok: false`.
2. **Redis** — alert jika Upstash/VPS Redis down (health akan `503` jika Redis wajib untuk operasi Anda).
3. **Sentry** — aturan alert untuk spike error atau error baru di release.
4. **Log** — rotasi log PM2/systemd; jangan log body request yang berisi PII.

## Environment

| Variabel | Fungsi |
|----------|--------|
| `APP_VERSION` | Opsional; muncul di JSON `/health` untuk memastikan instance deploy terbaru. |
| `REDIS_URL` | Wajib production untuk matching + rate limit. |
| `SENTRY_DSN` | Opsional tapi sangat disarankan. |

## Contoh interpretasi `/health`

```json
{
  "ok": true,
  "status": "traka-api",
  "checks": { "api": true, "redis": true, "pg": false },
  "uptimeSeconds": 3600,
  "version": "1.0.9"
}
```

`pg: false` tidak otomatis membuat `ok: false` (sesuai kode saat ini); sesuaikan monitoring jika PG wajib untuk fitur kritis.

## Rujukan

- [`SETUP_REDIS_PRODUCTION.md`](SETUP_REDIS_PRODUCTION.md)
- [`REDIS_GEO_MATCHING.md`](REDIS_GEO_MATCHING.md)
