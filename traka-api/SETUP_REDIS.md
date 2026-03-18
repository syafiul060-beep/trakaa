# Setup Redis untuk traka-api (Windows)

traka-api membutuhkan Redis untuk menyimpan status driver. Pilih salah satu opsi:

---

## Opsi A: Upstash (Paling Mudah - Tanpa Install)

1. Daftar gratis di https://upstash.com
2. Buat database Redis baru
3. Copy **Redis URL** (format: `redis://default:PASSWORD@HOST.upstash.io:6379`)
4. Edit `traka-api/.env`, ganti baris REDIS_URL:
   ```
   REDIS_URL=redis://default:YOUR_PASSWORD@YOUR_HOST.upstash.io:6379
   ```

---

## Opsi B: Memurai (Redis untuk Windows - Lokal)

**Jika Chocolatey gagal (MSI Error 1603):** Download manual lebih andal.

1. **Download** MSI dari https://www.memurai.com/get-memurai
2. **Install** dengan double-click installer (Run as Administrator)
3. Memurai berjalan di port 6379 secara default
4. Restart PC jika diminta (Error 1603 sering karena pending reboot)

---

## Verifikasi

Setelah Redis berjalan, jalankan traka-api:

```bash
cd traka-api
npm run dev
```

Jika berhasil: `Traka API running on http://localhost:3001`
