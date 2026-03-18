# Monitoring & Alerts untuk Produksi

## Sentry (traka-api)

Sudah dikonfigurasi di `instrument.js`:

- **tracesSampleRate:** 0.2 (produksi) – trace request untuk analisis latency
- **profilesSampleRate:** 0.1 (produksi) – profiling untuk bottleneck
- **beforeSend:** Filter /health dan ECONNRESET agar tidak trigger alert

### Alert yang Disarankan (Sentry Dashboard)

1. **Error rate** > 5% dalam 5 menit
2. **Transaction duration** p95 > 2 detik
3. **Failed requests** > 10 dalam 1 menit

## Firebase Cloud Functions

### Metrik di Firebase Console

- **Invocations** – jumlah pemanggilan
- **Execution time** – latency (cold start terlihat di sini)
- **Memory** – penggunaan memori
- **Errors** – error rate

### Alert yang Disarankan

1. **Cold start** – minInstances: 1 sudah mengurangi; monitor jika > 2 detik
2. **Error rate** > 1%
3. **Memory** mendekati limit (256 MB)

## Health Check

Endpoint `/health` di traka-api mengecek:

- API (selalu true)
- Redis (ping)
- PostgreSQL (SELECT 1)

Gunakan untuk uptime monitoring (UptimeRobot, Better Uptime, dll.).
