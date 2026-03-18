# Setup Tahap 2 – Rate Limit Redis & PM2 Clustering

## Yang Sudah Diterapkan

1. **Rate limit pakai Redis** – rate limit tersimpan di Redis, konsisten di semua instance
2. **PM2 config** – siap untuk clustering (multi-instance)

---

## Mode Development (seperti biasa)

```powershell
npm run dev
```

Rate limit otomatis pakai Redis store (jika REDIS_URL ada).

---

## Mode Production dengan PM2 (clustering)

```powershell
# Stop semua proses yang pakai port 3001 dulu
npm run start:cluster
```

PM2 akan menjalankan beberapa instance (sesuai jumlah CPU) untuk menangani request paralel.

**Perintah lain:**
- `npm run stop:cluster` – stop semua instance
- `npm run restart:cluster` – restart
- `pm2 status` – lihat status
- `pm2 logs` – lihat log

---

## Catatan

- **PM2** harus diinstall: `npm install` (sudah di devDependencies)
- Untuk production di Railway/Render: platform biasanya auto-scale, tidak perlu PM2
- Rate limit Redis hanya aktif jika `REDIS_URL` terisi
