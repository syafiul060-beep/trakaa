# traka-realtime-worker

Service **Tahap 4** (skeleton): Redis `SUBSCRIBE driver:location` → broadcast **Socket.IO** ke room `gh5:<precision-5>`.

Rujukan arsitektur: [`../traka/docs/TAHAPAN_4_Realtime_WebSocket.md`](../traka/docs/TAHAPAN_4_Realtime_WebSocket.md).

## Menjalankan lokal

```bash
cd traka-realtime-worker
cp .env.example .env
# isi REDIS_URL sama dengan traka-api
npm install
npm start
```

- HTTP + Socket.IO: `http://localhost:3100` (default)
- `GET /health` → JSON status

### Cara lengkap (Windows / PowerShell)

1. **Satu Redis yang sama dengan API**  
   Salin **`REDIS_URL`** dari Railway (variabel service `trakaa`) atau dari `traka-api/.env` lokal. Tempel ke `traka-realtime-worker/.env`:

   ```env
   REDIS_URL=redis://... atau rediss://...
   ```

2. **Jalankan worker** (terminal 1):

   ```powershell
   cd D:\Traka\traka-realtime-worker
   npm start
   ```

   Harus ada log: `[redis] subscribed to driver:location`.

3. **Cek health** (terminal atau browser):

   ```powershell
   Invoke-RestMethod -Uri "http://localhost:3100/health"
   ```

4. **Uji broadcast tanpa app** — dengan worker masih jalan, di **terminal 2**:

   ```powershell
   cd D:\Traka\traka-realtime-worker
   node scripts/publish-test.js
   ```

   (Membaca `REDIS_URL` dari `.env`.) Atau pakai **redis-cli**: `PUBLISH driver:location '{"uid":"test","city":"default","lat":-3.32,"lng":114.59,"ts":1730000000000}'`

5. **Uji Socket.IO** — buka HTML kecil atau gunakan klien Node: connect ke `http://localhost:3100`, `emit('join', { lat: -3.32, lng: 114.59 })`, `on('driver:location', console.log)`, lalu ulang **langkah 4** — event harus muncul.

6. **End-to-end dengan API** — di Railway **staging**, set `REDIS_PUBLISH_DRIVER_LOCATION=1`, panggil `POST /api/driver/location` (token driver) dari app atau Postman; worker yang memakai **Redis yang sama** akan broadcast ke room `gh5:...`.

7. **Deploy worker** — Railway: root `traka-realtime-worker`, start `npm start`, env `REDIS_URL` **identik** dengan service API (bisa service Redis terpisah asal URL sama).

## Troubleshooting

- **`Missing REDIS_URL`** — di file `.env` harus ada baris persis: `REDIS_URL=rediss://...` (pakai **nama variabel** `REDIS_URL=`; jangan hanya menempel URL tanpa itu). Simpan file sebagai **`.env`** (bukan `.env.txt`).

## Variabel lingkungan

| Variabel | Wajib | Keterangan |
|----------|--------|------------|
| `REDIS_URL` | Ya | Sama dengan API agar menerima `PUBLISH` dari `traka-api` |
| `PORT` | Tidak | Default `3100` |
| `ALLOWED_ORIGINS` | Tidak | CORS; `*` untuk dev |
| `SOCKET_AUTH_DEV_SECRET` | Tidak | Dev: klien kirim `auth.token` sama persis |
| `REALTIME_WS_TICKET_SECRET` | Disarankan produksi | Samakan dengan **traka-api**; klien pakai tiket dari `POST /api/realtime/ws-ticket` |

## API publish (sisi traka-api)

Set `REDIS_PUBLISH_DRIVER_LOCATION=1` dan pastikan driver memanggil `POST /api/driver/location`. Payload publish: [`../traka-api/docs/REALTIME_DRIVER_UPDATES.md`](../traka-api/docs/REALTIME_DRIVER_UPDATES.md).

## Klien Socket.IO (ringkas)

1. Connect ke URL worker (nanti `wss://` di belakang proxy).
2. `socket.emit('join', { lat, lng }, (res) => { ... })` — join room `gh5:...`.
3. `socket.on('driver:location', (data) => { ... })`.

## Produksi (berikutnya)

- **TLS** `wss://` (nginx/Caddy/Railway TCP).
- **Ticket JWT** dari `traka-api` — ganti middleware `io.use` di atas.
- **Scale:** `@socket.io/redis-adapter` + beberapa instance worker.
- Subscribe **9 sel** geohash (tengah + tetangga) di klien agar tidak ada “blind spot” di tepi sel — lihat dokumen Tahap 4.

## Deploy ke Railway (langkah 1 — urutan)

Asumsi: repo GitHub Anda sudah berisi folder **`traka-realtime-worker`** (monorepo `Traka`). Kalau folder ini **belum** ter-push, commit + push dulu.

### A. Tambah service baru

1. Buka [railway.app](https://railway.app) → project yang sama dengan API (**virtuous-respect** atau nama Anda).
2. Klik **+ New** → **GitHub Repo** → pilih repo **`trakaa`** (atau nama repo Anda).
3. Railway akan membuat **service baru** (bukan mengganti service `trakaa`).

### B. Root directory (penting untuk monorepo)

1. Klik service **baru** itu → tab **Settings**.
2. Cari **Root Directory** → isi: **`traka-realtime-worker`** (tanpa slash di depan).
3. Simpan. Ini membuat build hanya dari folder worker, bukan dari akar repo.

### C. Build & start

1. Tab **Settings** → **Build** (atau **Deploy**):
   - **Install command** (jika ada): `npm install` atau biarkan default Nixpacks.
   - **Start command:** **`npm start`** (sudah ada di `package.json`).
2. Railway **otomatis** mengisi **`PORT`** — kode `server.js` sudah memakai `process.env.PORT`; **jangan** set `PORT` manual kecuali perlu.

### D. Variabel lingkungan

Tab **Variables** → **New Variable**:

| Name | Value |
|------|--------|
| `REDIS_URL` | **Salin persis** dari service **trakaa** (API) → Variables → `REDIS_URL` (tombol copy / show). Harus sama agar subscribe/publish satu Redis. |
| `ALLOWED_ORIGINS` | Untuk uji: `*` atau domain app Anda nanti: `https://app.traka.id` (koma jika banyak). |

**Jangan** commit `REDIS_URL` ke Git; hanya di Railway.

### E. Domain publik

1. Tab **Settings** → **Networking** → **Generate domain** (atau **Public URL**).
2. Anda dapat URL seperti **`https://nama-service.up.railway.app`**.
3. Uji di browser: **`https://.../health`** → harus JSON `ok: true`, `service: "traka-realtime-worker"`.

### F. Socket.IO dari Flutter / HP

- Klien Socket.IO memakai **HTTPS** ke host yang sama (Railway menyediakan TLS).
- URL contoh: `https://nama-service.up.railway.app` (bukan `localhost`). Paket `socket_io_client` biasanya mengisi path `/socket.io/` otomatis.

### G. Masalah umum

| Gejala | Tindakan |
|--------|----------|
| **`Railpack could not determine how to build`** / deteksi **Php** / `start.sh not found` | Railway mem-build **bukan** dari folder Node. **Settings** → **Root Directory** = **`traka-realtime-worker`** (wajib). Commit + push file **`nixpacks.toml`** dan **`railway.toml`** di folder ini, lalu **Redeploy**. |
| Build tidak menemukan `package.json` | Pastikan **Root Directory** = `traka-realtime-worker`. |
| Crash saat start | Cek **Deploy Logs**; pastikan `REDIS_URL` ada dan valid. |
| Health OK tapi tidak subscribe | Lihat log: harus ada `[redis] subscribed to driver:location`. |

Setelah deploy OK, lanjut **langkah 2** di [`../traka/docs/TAHAPAN_4_Realtime_WebSocket.md`](../traka/docs/TAHAPAN_4_Realtime_WebSocket.md): set **`REDIS_PUBLISH_DRIVER_LOCATION=1`** di API.
