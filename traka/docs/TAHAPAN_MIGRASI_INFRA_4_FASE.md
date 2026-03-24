# Empat tahap migrasi infrastruktur & skala (operasional)

Dokumen ini melengkapi [`ROADMAP_INFRASTRUKTUR_SKALA.md`](ROADMAP_INFRASTRUKTUR_SKALA.md): **urutan eksekusi**, **apa yang bisa diotomatisasi di kode**, dan **apa yang harus Anda lakukan manual** (hosting, env, QA, keamanan).

**Prinsip:** jangan loncat tahap; tiap tahap punya **gate** (QA + metrik) sebelum lanjut.

---

## Gambaran singkat

| Tahap | Fokus | Gate sebelum lanjut |
|-------|--------|---------------------|
| **1** | Observabilitas: `/health`, Sentry, uptime, baseline error | `/health` stabil; alert uptime; QA regresi dasar |
| **2** | Optimasi murah: throttle UI, batas marker, query lebih hemat | Metrik lebih ringan; tidak ada regresi UX |
| **3** | Scale API + Redis sebagai pusat geo/matching | Redis & API stabil; hybrid (`TRAKA_USE_HYBRID`) teruji staging |
| **4** | Realtime massal: publish Redis → worker → WebSocket → klien | Worker + WS stabil; fallback Firestore tetap ada sementara |

Rujukan teknis API: [`../traka-api/docs/MONITORING_PRODUCTION.md`](../traka-api/docs/MONITORING_PRODUCTION.md), [`../traka-api/docs/REALTIME_DRIVER_UPDATES.md`](../traka-api/docs/REALTIME_DRIVER_UPDATES.md), [`../traka-api/docs/SETUP_REDIS_PRODUCTION.md`](../traka-api/docs/SETUP_REDIS_PRODUCTION.md).

---

## Tahap 1 — Observabilitas (data nyata sebelum mengubah arsitektur)

**Checklist eksekusi langkah demi langkah (PowerShell, Sentry, uptime):** [`../traka-api/docs/TAHAPAN_1_OBSERVABILITAS.md`](../traka-api/docs/TAHAPAN_1_OBSERVABILITAS.md).

### Tujuan

Anda bisa **membuktikan** kapan API bermasalah (bukan tebak-tebakan), dan punya baseline sebelum optimasi.

### Di repo / kode (sudah ada atau minor)

- Endpoint `GET /health` (cek `ok`, `checks.redis`, `version` jika `APP_VERSION` diset).
- Integrasi Sentry di API jika `SENTRY_DSN` diset (`MONITORING_PRODUCTION.md`).

### Yang Anda lakukan secara manual (terperinci)

1. **Sentry (produksi API)**  
   - Buat project di [sentry.io](https://sentry.io) untuk backend Node.  
   - Salin **DSN** → set sebagai environment variable `SENTRY_DSN` di platform deploy (Railway, VPS, dll.). **Jangan** commit DSN ke git.  
   - Di Sentry: buat **alert** untuk spike error rate atau error baru pada release.

2. **Uptime / synthetic check**  
   - Di UptimeRobot, Better Stack, atau fitur health check load balancer: **GET** `https://DOMAIN_ANDA/health` tiap **1–5 menit**.  
   - Alert jika status bukan 200 atau body `ok: false`.  
   - Catat URL final (HTTPS) yang sama dengan yang dipakai app produksi.

3. **Versi deploy terlihat**  
   - Set `APP_VERSION` (mis. semver atau git short SHA) di env produksi supaya `/health` bisa diverifikasi “instance mana yang jalan”.

4. **Baseline QA**  
   - Jalankan skenario di [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md) (minimal alur login, order, driver).  
   - Dokumentasikan tanggal + hasil (lulus/gagal + catatan).

5. **Log & privasi**  
   - Pastikan rotasi log (PM2/systemd) dan **jangan** log body request berisi PII (sesuai `MONITORING_PRODUCTION.md`).

**Gate tahap 1:** alert uptime aktif; Sentry menerima error uji (opsional: picu error staging); QA baseline tercatat.

---

## Tahap 2 — Optimasi murah (hemat Firestore/CPU tanpa infra baru)

**Panduan lengkap + lokasi kode + gate:** [`TAHAPAN_2_Optimasi_Murah.md`](TAHAPAN_2_Optimasi_Murah.md).

### Tujuan

Kurangi beban **tanpa** menambah WebSocket dulu: throttle render peta, batasi jumlah marker, query/listener lebih selektif.

### Di repo / kode

- Sesuaikan **interval update** lokasi driver ke API/Firestore (policy tier yang sudah ada di dokumen notifikasi/proximity).  
- **Throttle** redraw marker / animasi peta (mis. 80–120 ms) di layer UI penumpang/driver sesuai kebutuhan.  
- Batasi jumlah driver/marker yang dirender sekaligus (zoom + viewport).  
- Kurangi listener Firestore yang “lebar”; prefer query ter-scope (kota/order aktif).

### Yang Anda lakukan secara manual

1. **Pengukuran sebelum/sesudah**  
   - Di Firebase Console: bandingkan **Firestore reads** dan **Functions invocations** (jika relevan) sebelum vs sesudah deploy build yang berisi optimasi.  
   - Di perangkat nyata: cek apakah peta tetap halus (tidak “sekat” berlebihan karena throttle).

2. **QA regresi**  
   - Ulang skenario proximity, chat, dan order aktif; pastikan tidak ada delay yang merusak UX.

**Gate tahap 2:** metrik lebih ringan atau sama dengan UX tidak memburuk; QA lulus.

---

## Tahap 3 — Horizontal scale API + Redis sebagai pusat geo

**Panduan lengkap + build hybrid + gate:** [`TAHAPAN_3_Scale_API_Redis_Hybrid.md`](TAHAPAN_3_Scale_API_Redis_Hybrid.md).

### Tujuan

Beberapa instance API bisa jalan paralel; **Redis** tetap sumber kebenaran untuk geo/matching + rate limit; opsi **hybrid** driver status lewat API.

### Di repo / kode (konfigurasi klien)

- Flutter: `TrakaApiConfig` — `TRAKA_API_BASE_URL`, `TRAKA_USE_HYBRID`, opsional `TRAKA_API_CERT_SHA256` untuk pinning (`traka/lib/config/traka_api_config.dart`).  
- Build release: pass `--dart-define=...` sesuai environment (lihat dokumentasi build Anda, mis. [`BUILD_PLAY_STORE.md`](BUILD_PLAY_STORE.md)).

### Yang Anda lakukan secara manual (terperinci)

1. **Redis produksi**  
   - Ikuti [`SETUP_REDIS_PRODUCTION.md`](../traka-api/docs/SETUP_REDIS_PRODUCTION.md): pilih provider, region dekat API, **TLS** (`rediss://`), set `REDIS_URL` di server API.  
   - Aktifkan alert memori (mis. >80%).  
   - **Jangan** expose Redis ke internet publik tanpa ACL/firewall; hanya dari API/worker.

2. **Deploy API bisa di-scale**  
   - Pastikan semua instance memakai **env yang sama** (`REDIS_URL`, secret DB, dll.).  
   - Rate limit & geo di Redis **shared** antar instance (sudah dirancang untuk itu).  
   - Set `APP_VERSION` per deploy.

3. **Mengaktifkan hybrid di app (bertahap)**  
   - **Staging dulu:** build dengan `TRAKA_API_BASE_URL` + `TRAKA_USE_HYBRID=true` (dan fingerprint jika dipakai).  
   - Uji penuh driver online/offline, order.  
   - **Produksi:** rollout bertahap (kelompok internal / beta) sebelum 100% pengguna.

4. **Certificate pinning (opsional tapi disarankan untuk HTTPS)**  
   - Ambil fingerprint SHA-256 dari sertifikat server (`openssl` / dokumen `SETUP_CERTIFICATE_PINNING.md` jika ada).  
   - Set `TRAKA_API_CERT_SHA256` di build; salah fingerprint = koneksi gagal — uji dengan hati-hati.

5. **Rollback plan**  
   - Simpan build lama dengan `TRAKA_USE_HYBRID=false` atau tanpa URL API; bisa distrikkan cepat jika ada incident.

**Gate tahap 3:** multi-instance sehat; `/health` `redis: true`; hybrid staging stabil; baru naik produksi bertahap.

---

## Tahap 4 — Realtime massal (Redis → worker → WebSocket → klien)

**Panduan lengkap + fase 4A–4D + gate:** [`TAHAPAN_4_Realtime_WebSocket.md`](TAHAPAN_4_Realtime_WebSocket.md).

### Tujuan

Posisi driver didorong ke penumpang **tanpa** polling Firestore berat; skala dengan room/grid geografis.

### Di repo / kode (arah kerja — tidak semua mungkin sudah jadi sekaligus)

- API: `REDIS_PUBLISH_DRIVER_LOCATION=1` → publish ke channel `driver:location` (payload di [`REALTIME_DRIVER_UPDATES.md`](../traka-api/docs/REALTIME_DRIVER_UPDATES.md)).  
- **Worker terpisah:** `SUBSCRIBE driver:location` → broadcast ke **Socket.IO** atau **WebSocket** (room per grid/geohash).  
- App penumpang: subscribe room sesuai posisi user; throttle render; **tidak** kirim API key/JWT ke channel publik.

### Yang Anda lakukan secara manual (terperinci)

1. **Infra WebSocket**  
   - Deploy service worker+WS di mesin yang sama atau terpisah dari API REST.  
   - **TLS:** wajib `wss://` di produksi (reverse proxy nginx/Caddy atau load balancer dengan sertifikat valid).  
   - Firewall: hanya port yang perlu; WS sering lewat 443.

2. **Secret & auth**  
   - Tentukan model auth koneksi WS (JWT singkat, atau ticket dari REST). **Jangan** expose secret di payload Redis publik.

3. **Env API**  
   - Set `REDIS_PUBLISH_DRIVER_LOCATION=1` hanya setelah worker siap memproses (atau Anda akan membebani Redis tanpa konsumen — masih bisa ditolerir singkat, tapi idealnya worker hidup dulu).

4. **Load & fallback**  
   - Saat rollout: pertahankan **fallback** baca Firestore atau polling API sampai WS stabil.  
   - Monitor: error koneksi WS, reconnect storm, latency Redis.

5. **DNS & scaling WS**  
   - Jika banyak instance WS, butuh **sticky session** atau shared pub/sub antar node (Redis adapter untuk Socket.IO, dll.).

6. **QA**  
   - Uji jaringan buruk (4G lemah), background/foreground app, dan baterai.

**Gate tahap 4:** WS stabil di staging dengan beban tiruan; rollback ke mode lama teruji; baru produksi bertahap.

---

## Urutan kerja engineering (disarankan)

1. Selesaikan **Tahap 1** (monitoring + QA baseline).  
2. **Tahap 2** di branch/PR terpisah; merge setelah QA.  
3. **Tahap 3** — infra Redis + scale API + hybrid bertahap.  
4. **Tahap 4** — worker + WS; `REDIS_PUBLISH_DRIVER_LOCATION` + klien; dual-write/fallback sampai stabil.

---

## Checklist cepat “manual saja”

| Item | Tahap |
|------|--------|
| Set `SENTRY_DSN`, `APP_VERSION`, uptime check `/health` | 1 |
| Firebase metrics before/after, QA regresi | 2 |
| `REDIS_URL`, alert Redis, scale instance API, `--dart-define` hybrid & pinning | 3 |
| Deploy worker+WS, TLS `wss://`, auth WS, `REDIS_PUBLISH_DRIVER_LOCATION=1`, sticky/shared bus | 4 |

---

## Dokumen terkait

- [`ROADMAP_INFRASTRUKTUR_SKALA.md`](ROADMAP_INFRASTRUKTUR_SKALA.md)  
- [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md)  
- [`../traka-api/docs/MONITORING_PRODUCTION.md`](../traka-api/docs/MONITORING_PRODUCTION.md)  
- [`../traka-api/docs/REALTIME_DRIVER_UPDATES.md`](../traka-api/docs/REALTIME_DRIVER_UPDATES.md)  
- [`../traka-api/docs/SETUP_REDIS_PRODUCTION.md`](../traka-api/docs/SETUP_REDIS_PRODUCTION.md)

*Tinjau dokumen ini tiap kuartal atau setelah lonjakan pengguna.*
