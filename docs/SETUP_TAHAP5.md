# Tahap 5 – Monitoring

## Yang Diterapkan

### 1. Sentry (traka-api)
- Error tracking untuk API
- Hanya aktif jika `SENTRY_DSN` di-set di `.env`

### 2. Firebase Performance (traka – Flutter)
- Monitoring performa app (app start, network, dll.)
- Data tampil di Firebase Console → Performance

---

## Setup Sentry

### Langkah 1: Buat project di Sentry
1. Daftar di [sentry.io](https://sentry.io)
2. Buat project baru → pilih **Node.js**
3. Copy **DSN** (format: `https://xxx@xxx.ingest.sentry.io/xxx`)

### Langkah 2: Tambah ke .env
```
SENTRY_DSN=https://xxx@xxx.ingest.sentry.io/xxx
```

### Langkah 3: Restart API
```powershell
npm run dev
# atau
npm run restart:cluster
```

---

## Firebase Performance

Sudah diaktifkan di `main.dart`. Data otomatis dikirim ke Firebase Console.

**Lihat data:**
1. Firebase Console → **Performance**
2. Tunggu ~30 menit untuk data pertama muncul

---

## Metrik yang Disarankan

| Metrik | Sumber | Tindakan |
|--------|--------|----------|
| Error rate | Sentry | Alert jika > 1% |
| Request latency | Load balancer / APM | Alert jika p95 > 2s |
| App start time | Firebase Performance | Monitor |
| Cold start | Firebase Functions | Monitor, tambah minInstances jika perlu |
