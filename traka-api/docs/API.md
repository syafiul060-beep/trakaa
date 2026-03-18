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
- `GET /api/orders` - Daftar order user (auth required)
  - Query: `role` (driver|passenger), `limit` (default 50, max 100), `offset` (default 0)
- `GET /api/orders/:id` - Detail order (auth required)

## Rate Limiting
- 100 requests per 15 menit per IP
- Header: `RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`

## CORS
Set `ALLOWED_ORIGINS` di env (comma-separated). Default `*` untuk development.
