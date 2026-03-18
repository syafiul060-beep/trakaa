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

## Upstash (Rekomendasi)

- Set `REDIS_URL` di env (format: `rediss://default:PASSWORD@HOST.upstash.io:6379` untuk TLS)
- Dashboard: monitor memory usage, hit rate
- Auto-scaling tersedia di plan Pro

## Alert yang Disarankan

- Memory usage > 80%
- Connection errors
- Latency > 100 ms
