# Tahap 1 — Observabilitas (checklist eksekusi)

Tujuan: **tahu kapan API sehat** (`/health`), **error masuk Sentry**, **uptime di-monitor**, dan **QA baseline** tercatat — sebelum optimasi (Tahap 2) atau scale (Tahap 3).

Prasyarat di kode (sudah di repo): `GET /health`, `instrument.js` + `SENTRY_DSN`. Lihat [`MONITORING_PRODUCTION.md`](MONITORING_PRODUCTION.md).

---

## Railway — jika `/health` sudah OK, kerjakan ini berurutan

Ganti `https://SERVICE-ANDA.up.railway.app` dengan URL publik API Anda (contoh: `https://trakaa-production.up.railway.app`).

### A. `APP_VERSION` + field `version`

1. Buka [Railway](https://railway.app) → project **Traka API** → klik **service** yang menjalankan Node (`traka-api`).
2. Tab **Variables** (atau **Settings** → Variables, tergantung UI).
3. **New Variable**:
   - **Name:** `APP_VERSION`
   - **Value:** mis. `1.0.0` atau 7 karakter pertama commit git (`git rev-parse --short HEAD`).
4. Simpan. Railway biasanya **redeploy otomatis**; jika tidak, tab **Deployments** → **Redeploy** deploy terbaru.
5. Buka di browser: `https://SERVICE-ANDA.up.railway.app/health` — JSON harus berisi **`version`** (dan **`uptimeSeconds`**).

### B. Monitor uptime → `/health`

1. Daftar di [UptimeRobot](https://uptimerobot.com) (gratis) → **Add New Monitor**.
2. **Monitor Type:** HTTP(s).
3. **Friendly name:** mis. `Traka API health`.
4. **URL:** `https://SERVICE-ANDA.up.railway.app/health` (HTTPS, path `/health`).
5. **Monitoring Interval:** 5 menit (cukup untuk awal).
6. **Alert contacts:** tambah email (verifikasi email dulu).
7. Simpan. Setelah beberapa menit, status harus **Up**. Opsional: di Railway **scale to zero** di service lain untuk tes — **jangan** matikan API produksi hanya untuk tes tanpa jadwal maintenance.

### C. Sentry + redeploy

1. [sentry.io](https://sentry.io) → **Projects** → **Create Project** → platform **Node.js** → salin **DSN**.
2. Railway → service API → **Variables** → tambah:
   - `SENTRY_DSN` = tempel DSN penuh.
   - `SENTRY_ENVIRONMENT` = `production` (agar issue tidak tercampur staging).
3. Simpan → tunggu redeploy selesai.
4. **Uji:** buka **Issues** di Sentry. Untuk memastikan pipeline jalan, lebih aman uji di **staging** dulu; di produksi bisa menunggu error alami atau buat service staging dengan DSN berbeda + `SENTRY_ENVIRONMENT=staging`.
5. Di Sentry: **Alerts** → buat aturan untuk spike error (wizard bawaan).

### D. QA sekali + catatan

1. Buka [`../../traka/docs/QA_REGRESI_ALUR_UTAMA.md`](../../traka/docs/QA_REGRESI_ALUR_UTAMA.md).
2. Jalankan minimal skenario yang relevan (login, order, driver).
3. Catat di satu tempat (Notion / spreadsheet): **tanggal**, **versi app / build**, **lulus atau gagal**, **catatan singkat**.

---

## 1. Versi deploy (`APP_VERSION`)

1. Di panel hosting (Railway, Render, VPS, dll.), tambahkan environment variable:
   - **Nama:** `APP_VERSION`
   - **Nilai:** mis. `1.0.9` atau short SHA git `a1b2c3d`
2. Redeploy agar env terbaca.
3. Cek respons JSON memuat `version`:

```powershell
# Ganti URL produksi Anda
Invoke-RestMethod -Uri "https://DOMAIN_ANDA/health" -Method Get
```

Field `version` **hanya muncul** jika `APP_VERSION` diset (lihat `src/index.js`).

---

## 2. Uptime / synthetic monitoring

1. Pilih salah satu: [UptimeRobot](https://uptimerobot.com), [Better Stack](https://betterstack.com), health check load balancer, dll.
2. Buat monitor:
   - **URL:** `https://DOMAIN_ANDA/health` (HTTPS, sama dengan domain publik API).
   - **Interval:** 1–5 menit.
   - **Metode:** GET.
3. **Alert:** email/Telegram/Slack jika non-200.
4. **Catatan:** `/health` mengembalikan **503** jika `ok: false` (mis. Redis down). Monitor harus memperlakukan 503 sebagai **down** untuk API operasional penuh.

### Interpretasi body `/health`

| Field | Arti |
|--------|------|
| `ok: true` | API + Redis sehat (syarat produksi normal). |
| `ok: false` | Biasanya Redis tidak terhubung — cek `REDIS_URL` dan instance Redis. |
| `checks.pg` | Opsional; `false` tidak selalu membuat `ok: false` (sesuai kode saat ini). |

Contoh sehat:

```json
{
  "ok": true,
  "status": "traka-api",
  "checks": { "api": true, "redis": true, "pg": false },
  "version": "1.0.9",
  "uptimeSeconds": 3600
}
```

---

## 3. Sentry (error tracking)

1. Buat akun/project di [sentry.io](https://sentry.io) — tipe **Node.js / Express**.
2. Salin **DSN** (bukan commit ke git).
3. Di hosting, set:
   - `SENTRY_DSN=https://...@....ingest.sentry.io/...`
   - Disarankan: `SENTRY_ENVIRONMENT=production` agar tidak tercampur dengan staging.
4. Redeploy.
5. **Uji (staging):** picu error sengaja pada route uji atau panggil endpoint yang error — pastikan event muncul di Sentry.
6. Di Sentry: buat **alert** untuk spike error atau regresi release.

**Catatan:** `instrument.js` memfilter noise dari `/health` (ECONNRESET dari monitor) agar tidak membanjiri Sentry.

---

## 4. Baseline QA (app)

1. Buka [`../../traka/docs/QA_REGRESI_ALUR_UTAMA.md`](../../traka/docs/QA_REGRESI_ALUR_UTAMA.md).
2. Jalankan minimal: login, order, driver (sesuai lingkungan Anda).
3. Catat di spreadsheet/notion: **tanggal**, **build/app version**, **lulus/gagal**, **catatan**.

---

## 5. Log & privasi

1. Pastikan log server **berotasi** (PM2 `logrotate`, journald, dll.).
2. **Jangan** log body request yang berisi nomor telepon, alamat lengkap, atau data sensitif lain.

---

## Verifikasi lokal (developer)

Setelah `REDIS_URL` dan dependency OK:

```powershell
cd traka-api
# Salin .env dari .env.example dan isi REDIS_URL
npm install
npm start
```

Di terminal lain:

```powershell
Invoke-RestMethod -Uri "http://localhost:3001/health"
```

`ok` harus `true` jika Redis bisa di-ping.

---

## Gate Tahap 1 selesai jika

- [ ] `GET /health` produksi **200** dan `ok: true` (saat stack normal).
- [ ] `version` terlihat di JSON (setelah `APP_VERSION`).
- [ ] Monitor uptime aktif dan pernah diuji alert (bisa matikan sementara Redis di **staging** untuk tes 503 — hati-hati di produksi).
- [ ] `SENTRY_DSN` aktif dan Anda melihat minimal satu event uji di staging (atau produksi setelah deploy).
- [ ] Satu putaran QA baseline terdokumentasi.

**Lanjut:** [`../../traka/docs/TAHAPAN_MIGRASI_INFRA_4_FASE.md`](../../traka/docs/TAHAPAN_MIGRASI_INFRA_4_FASE.md) — Tahap 2.
