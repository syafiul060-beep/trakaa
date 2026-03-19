# Redis untuk Produksi 1–5 Juta Pengguna

## Penggunaan di Traka

- **driver_status:** Status driver online (TTL 600s per key)
- **Rate limiting:** 100 req/15 menit per IP (shared across PM2 instances)

## Rekomendasi Instance

| Pengguna | Memory | Provider |
|----------|--------|----------|
| < 100k | 256 MB | Upstash Free, Redis Cloud Free |
| 100k – 1 jt | 512 MB – 1 GB | Upstash Pro, Redis Cloud |
| 1–5 jt | 1–2 GB | Upstash Pro, Redis Cloud, AWS ElastiCache |

## Konfigurasi Produksi

1. **maxmemory-policy:** `volatile-lru` (hapus key dengan TTL saat penuh)
2. **Persistence:** Optional untuk driver_status (data sementara); wajib jika rate limit harus persist
3. **Connection:** Gunakan connection pooling (Redis client sudah handle)

---

## Langkah Setup Produksi

### 1. Pilih Provider

- **Upstash** (rekomendasi): Serverless, pay-per-request, mudah setup
- **Redis Cloud**: Managed Redis dengan alert bawaan
- **AWS ElastiCache**: Untuk stack AWS penuh

### 2. Buat Instance sesuai Skala

Contoh untuk **100k–1 juta pengguna**:
- Pilih plan **512 MB – 1 GB**
- Region: pilih terdekat dengan server API (mis. `ap-southeast-1` untuk Singapore)
- TLS: aktifkan (wajib untuk produksi)

### 3. Salin Connection URL ke Env

```bash
REDIS_URL=rediss://default:PASSWORD@HOST.upstash.io:6379
```

> Format `rediss://` (dengan double-s) untuk koneksi TLS. Pastikan variabel ini ada di `.env` produksi.

### 4. Aktifkan Alert Memory > 80%

#### Upstash

Upstash **tidak punya alert bawaan** di dashboard. Opsi:

**A. Monitoring manual**
- Buka [console.upstash.com](https://console.upstash.com) → pilih database
- Cek chart **Data Size** (24 jam terakhir) secara berkala
- Jika mendekati limit, upgrade plan atau optimasi key

**B. Prometheus + Grafana (plan Pro)**
1. Di database → **Integrations** → aktifkan **Prometheus**
2. Salin monitoring token
3. Setup Prometheus scrape ke `https://api.upstash.com/monitoring/prometheus`
4. Import [Upstash Grafana Dashboard](https://grafana.com/grafana/dashboards/22257-upstash-redis-dashboard/) → buat alert dari panel Data Size / memory
5. Hubungkan notifikasi ke Slack/email/PagerDuty

#### Redis Cloud

Redis Cloud punya **alert bawaan**:

1. Buka [Redis Cloud Console](https://app.redislabs.com)
2. Pilih **database** → **Configuration** → **Edit**
3. Buka tab **Alerts**
4. Centang **High memory usage** (atau set threshold 80%)
5. Klik **Save**
6. Untuk notifikasi email: **Cluster** → **Alert Settings** → **Edit** → **Set an email** → isi SMTP
7. Di **Access Control**, aktifkan **Receive email alerts** untuk user yang ingin menerima

---

## Alert yang Disarankan

- Memory usage > 80%
- Connection errors
- Latency > 100 ms
