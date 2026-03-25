# Traka API Documentation

## Base URL
`/api`

## Authentication
Endpoints yang memerlukan auth menggunakan header:
```
Authorization: Bearer <Firebase ID Token>
```

## Endpoints

### Health
- `GET /health` - Cek status API (tidak perlu auth). JSON: `ok` + `live` + `checks: { api, redis, pg }`. **HTTP:** default **200** selama proses hidup (Redis opsional); **`ok`** false jika Redis belum OK. **`HEALTHCHECK_STRICT=1`** → HTTP **503** bila Redis down (readiness ketat).

### Realtime (Tahap 4 — tiket Socket.IO)
- `POST /api/realtime/ws-ticket` — mint tiket HMAC untuk handshake worker (`traka-realtime-worker`). **Auth:** Bearer Firebase (penumpang/driver). Response: `{ ticket, expiresIn }`. **503** jika `REALTIME_WS_TICKET_SECRET` belum diset di API. Secret yang **sama** harus diset di worker.

### Driver
- `GET /api/driver/status` - Daftar driver aktif (dari Redis)
  - Query: `limit` (default 50, max 100), `cursor` (untuk pagination)
  - Response: `{ drivers, nextCursor }` (nextCursor null = selesai)
- `GET /api/driver/:uid/status` - Status driver tertentu
- `POST /api/driver/location` - Update lokasi driver (auth required)
  - Body: `{ latitude, longitude, status?, routeOriginLat?, ... }`

### Users
- `GET /api/users/:uid` - Data user (auth required)

### Orders
- `POST /api/orders` - Buat order penumpang (auth required, Bearer = penumpang)
  - Body (JSON): selaras `OrderService.createOrder` di Flutter — field utama `passengerUid`, `driverUid`, `routeJourneyNumber`, `passengerName`, `originText`, `destText`, `orderType` (`travel` | `kirim_barang`), koordinat opsional, kirim barang / jadwal / penerima, dll. **Jangan** kirim `createdAt` / `updatedAt` (server set `serverTimestamp` di Firestore).
  - Flag opsional: `bypassDuplicatePendingTravel`, `bypassDuplicatePendingKirimBarang` (boolean) — sama semantiknya dengan app.
  - **201** `{ id, status, orderType, driverUid, routeJourneyNumber }`
  - **400** `{ error }` — validasi (mis. field wajib kosong)
  - **403** `{ error: 'passengerUid must match authenticated user' | 'admin_verification_blocking' }`
  - **409** `{ error: 'duplicate_pending_travel' | 'duplicate_pending_kirim_barang', existingOrderId }`
  - **500** `{ error }` — gagal tulis Firestore/PostgreSQL (jika PG gagal, dokumen Firestore yang baru dibuat dihapus)
  - **503** `{ error }` — Firestore Admin tidak terkonfigurasi
  - Dual-write: Firestore (sumber utama app) + PostgreSQL jika `DATABASE_URL` aktif. Detail aturan: [ORDER_CREATE_HYBRID.md](./ORDER_CREATE_HYBRID.md).
- `GET /api/orders` - Daftar order user (auth required)
  - Query: `role` (driver|passenger), `limit` (default 50, max 100), `offset` (default 0)
- `GET /api/orders/:id` - Detail order (auth required)

### Driver payment methods (instruksi bayar non-escrow)
- `GET /api/driver/payment-methods` — daftar metode milik driver (auth)
- `POST /api/driver/payment-methods` — body: `type` (`bank`|`ewallet`|`qris`), `accountHolderName`, plus field sesuai jenis. Nama harus cocok profil atau `pending_review`.
- `PATCH /api/driver/payment-methods/:id` — ubah data
- `DELETE /api/driver/payment-methods/:id` — suspend (hapus dari tampilan penumpang)

### Order: instruksi bayar untuk penumpang
- `GET /api/orders/:orderId/driver-payment-methods` — hanya peserta order; kembalikan metode **active** driver (tanpa `normalized_key`).

### Admin
- `GET /api/admin/payment-methods/pending` — antrian `pending_review` (admin + Bearer)
- `POST /api/admin/payment-methods/:id/approve` — body opsional `{ adminNote }`
- `POST /api/admin/payment-methods/:id/reject` — body opsional `{ adminNote }`

## Rate Limiting
- 100 requests per 15 menit per IP
- Header: `RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`

## CORS
Set `ALLOWED_ORIGINS` di env (comma-separated). Default `*` untuk development.
