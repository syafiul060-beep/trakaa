# Database Traka: Firebase & Hybrid

Dokumen ini menjelaskan penggunaan database di aplikasi Traka dan status mode hybrid.

---

## 1. Ringkasan Arsitektur

| Komponen | Firebase (Default) | Hybrid (TRAKA_USE_HYBRID=true) |
|----------|-------------------|--------------------------------|
| **driver_status** | Firestore | Redis (via traka-api) |
| **orders** | Firestore | Firestore* |
| **users** | Firestore | Firestore* |
| **orders/{id}/messages** (chat) | Firestore | Firestore |
| **app_config** | Firestore | Firestore |
| **verification_codes** | Firestore | Firestore |
| **violation_records** | Firestore | Firestore |
| **contribution_payments** | Firestore | Firestore |
| **vehicle_data** | Firestore | Firestore |

\* traka-api punya endpoint GET /api/orders dan GET /api/users yang baca dari PostgreSQL, **tetapi Flutter app belum memakainya**. Semua order/user di Flutter masih dari Firestore.

---

## 2. Yang Sudah Hybrid (driver_status)

### Flutter
- **DriverStatusService**: `updateDriverStatus`, `removeDriverStatus`, `getActiveRouteFromFirestore`, `streamDriverPosition`, `streamDriverStatusData` — switch Firestore vs API berdasarkan `TrakaApiConfig.isApiEnabled`
- **ActiveDriversService**: `getActiveDriverRoutes` — baca dari API atau Firestore
- **TrakaApiService**: POST /location, DELETE /status, GET /status, GET /:uid/status, streamDriverStatus (polling 4 detik)

### traka-api
- **Redis**: driver_status disimpan di Redis (key: `driver_status:{uid}`), TTL 10 menit
- **driver.js**: GET /status (daftar driver), POST /location (update), GET /:uid/status (satu driver), DELETE /status (hapus)

### Keterbatasan Hybrid driver_status
- **currentPassengerCount**: Saat hybrid, partial update tidak dikirim ke API. Nilai ter-update saat driver kirim lokasi berikutnya (API tidak support partial update).
- **Stream**: Firestore pakai real-time snapshot; API pakai polling 4 detik (latency lebih tinggi).

---

## 3. Yang Belum Hybrid (orders, users)

### traka-api (sudah ada)
- **orders.js**: GET / (list by driver/passenger), GET /:id (detail) — baca dari PostgreSQL
- **users.js**: GET /:uid — baca dari PostgreSQL

### Flutter (belum pakai API)
- **OrderService**: Semua operasi order (create, stream, update, dll.) langsung ke Firestore
- **ChatService**: messages di subcollection Firestore
- **User data**: Dibaca dari Firestore (users collection)
- **Tidak ada** TrakaApiService.getOrders atau getUsers — Flutter tidak memanggil API orders/users

### PostgreSQL schema
- **orders**: Tabel ada di schema.sql, **belum ada kolom barang** (barangCategory, barangNama, barangBeratKg, dll.)
- **users**: Tabel ada

---

## 4. Koleksi Firestore yang Dipakai

| Koleksi | Dipakai oleh | Hybrid? |
|---------|--------------|---------|
| `driver_status` | DriverStatusService, ActiveDriversService | ✓ Ya (Redis) |
| `orders` | OrderService, ChatService, PaymentHistoryService, dll. | ✗ Belum |
| `orders/{id}/messages` | ChatService | ✗ Belum |
| `users` | Login, Register, Profile, OrderService.findUserByEmailOrPhone | ✗ Belum |
| `app_config` | AppConfigService, LacakBarangService | ✗ Tetap Firestore |
| `verification_codes` | Register, Forgot password | ✗ Tetap Firestore |
| `violation_records` | OrderService, PaymentHistoryService | ✗ Belum |
| `contribution_payments` | PaymentHistoryService | ✗ Belum |
| `vehicle_data` | ActiveDriversService | ✗ Tetap Firestore |
| `route_sessions` | (driver rute) | ✗ Tetap Firestore |
| `trips` | TripService | ✗ Tetap Firestore |
| `counters` | OrderNumberService, RouteJourneyNumberService | ✗ Tetap Firestore |

---

## 5. Mode Hybrid yang Sesuai Aplikasi Ini

### Opsi A: Hybrid Minimal (Saat Ini)
- **driver_status** → Redis ✓
- **orders, users, chat** → Tetap Firestore
- **Cukup** untuk mengurangi biaya Firestore (driver_status adalah write terbanyak)
- **Tidak perlu** migrasi orders/users ke PostgreSQL

### Opsi B: Hybrid Penuh (Orders + Users ke PostgreSQL)
- **driver_status** → Redis ✓
- **orders** → PostgreSQL (perlu ubah OrderService di Flutter untuk baca/tulis via API)
- **users** → PostgreSQL (perlu ubah banyak service yang baca users)
- **messages (chat)** → Tetap Firestore (real-time, sulit diganti) ATAU pindah ke PostgreSQL + polling/WebSocket
- **Perlu**: Dual-write Firestore + PostgreSQL saat transisi, migrasi data, update Flutter

### Opsi C: Hybrid Bertahap (Disarankan)
1. **Fase 1**: Aktifkan hybrid driver_status saja (sudah siap)
2. **Fase 2**: (Opsional) Orders read dari API/PostgreSQL untuk Data Order, write tetap Firestore + sync ke PG
3. **Fase 3**: (Opsional) Users read dari API jika perlu

---

## 6. Yang Perlu Dilakukan untuk Aktifkan Hybrid (Fase 1)

1. **Setup infrastruktur**
   - Upstash Redis
   - Supabase PostgreSQL (untuk schema, bisa kosong dulu)
   - Deploy traka-api (Railway/Render)

2. **Konfigurasi**
   - traka-api `.env`: REDIS_URL, DATABASE_URL, FIREbase service account
   - Flutter build: `--dart-define=TRAKA_API_BASE_URL=... --dart-define=TRAKA_USE_HYBRID=true`

3. **Tidak perlu** migrasi orders/users — tetap pakai Firestore

---

## 7. Jika Ingin Orders ke PostgreSQL (Fase 2+)

1. **Schema PostgreSQL**: Tambah kolom barang di tabel orders:
   ```sql
   ALTER TABLE orders ADD COLUMN IF NOT EXISTS "barangCategory" TEXT;
   ALTER TABLE orders ADD COLUMN IF NOT EXISTS "barangNama" TEXT;
   ALTER TABLE orders ADD COLUMN IF NOT EXISTS "barangBeratKg" DOUBLE PRECISION;
   ALTER TABLE orders ADD COLUMN IF NOT EXISTS "barangPanjangCm" DOUBLE PRECISION;
   ALTER TABLE orders ADD COLUMN IF NOT EXISTS "barangLebarCm" DOUBLE PRECISION;
   ALTER TABLE orders ADD COLUMN IF NOT EXISTS "barangTinggiCm" DOUBLE PRECISION;
   ```

2. **traka-api**: Perlu endpoint POST/PATCH orders (create, update) — saat ini hanya GET

3. **Flutter OrderService**: Refactor untuk pakai API saat hybrid — scope besar (create, stream, update, delete, batch)

4. **Chat/messages**: Tetap Firestore (real-time) atau bangun sistem chat baru

5. **Cloud Functions**: Banyak trigger Firestore (onOrderCreated, onOrderUpdatedScan, dll.) — perlu sinkron ke PostgreSQL atau pindah logic ke API

---

## 8. Kesimpulan

**Hybrid mode saat ini** = driver_status ke Redis saja. Orders, users, chat tetap Firestore.

**Untuk aktifkan**: Deploy traka-api, set TRAKA_USE_HYBRID=true, TRAKA_API_BASE_URL. Tidak perlu ubah orders/users.

**Untuk hybrid penuh (orders ke PostgreSQL)**: Perlu development signifikan — refactor OrderService, Cloud Functions sync, schema update, migrasi data.
