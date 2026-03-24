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
- `GET /health` - Cek status API (tidak perlu auth). Response: `{ ok, status, checks: { api, redis, pg } }`

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

## Rate Limiting
- 100 requests per 15 menit per IP
- Header: `RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`

## CORS
Set `ALLOWED_ORIGINS` di env (comma-separated). Default `*` untuk development.
