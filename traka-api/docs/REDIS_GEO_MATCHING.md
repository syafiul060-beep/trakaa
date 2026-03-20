# Redis GEO – Backend Matching (#9)

Dokumentasi arsitektur dan langkah implementasi **driver matching** berbasis Redis GEO untuk skala besar.

---

## 1. Ringkasan

| Komponen | Peran |
|----------|------|
| **Redis GEO** | Simpan lokasi driver, cari driver terdekat dari titik pickup |
| **Pub/Sub** | Event realtime (order baru, update status) – opsional |
| **API Server** | Matching, routing, validasi |

---

## 2. Schema Redis

### Key yang dipakai

| Key | Tipe | Keterangan |
|-----|------|------------|
| `drivers:geo:{city}` | GEO (sorted set) | Lokasi driver per kota. `{city}` = slug kota (mis. `bandung`, `jakarta`) |
| `driver:{uid}` | Hash / String (JSON) | Metadata driver: status, route, journey number, dll. TTL 600s |
| `order:{orderId}` | Hash / String | Order yang butuh matching (opsional, untuk tracking) |

### GEOADD – simpan lokasi driver

```redis
GEOADD drivers:geo:bandung 107.6 -6.9 driver_uid_123
```

- Member = `driver_{uid}` agar unik dan mudah parse
- Longitude, Latitude (urutan GEOADD: lon, lat)

### GEORADIUS – cari driver terdekat

```redis
GEORADIUS drivers:geo:bandung 107.61 -6.92 5 km WITHDIST ASC COUNT 20
```

- Cari driver dalam radius 5 km dari titik pickup
- `WITHDIST` = kembalikan jarak
- `ASC` = terdekat dulu
- `COUNT 20` = max 20 driver

---

## 3. Flow Matching

```
1. Driver online → POST /api/driver/location
   → GEOADD drivers:geo:{city} {lng} {lat} driver_{uid}
   → SET driver:{uid} {metadata} EX 600

2. Order baru (pickup lat/lng) → API matching
   → GEORADIUS drivers:geo:{city} {lng} {lat} 5 km WITHDIST ASC COUNT 20
   → Filter: status siap, route cocok (opsional)
   → Return daftar driver terdekat + jarak

3. Driver offline → DELETE /api/driver/status
   → ZREM drivers:geo:{city} driver_{uid}
   → DEL driver:{uid}
```

---

## 4. Implementasi di traka-api

### 4.1 Perluas `src/lib/redis.js`

```javascript
// GEO helpers (Redis 3.2+)
async function geoAddDriver(city, uid, lng, lat) {
  const redis = getRedis();
  if (!redis) return;
  const key = `drivers:geo:${city}`;
  await redis.sendCommand(['GEOADD', key, lng, lat, `driver_${uid}`]);
}

async function geoRemoveDriver(city, uid) {
  const redis = getRedis();
  if (!redis) return;
  await redis.sendCommand(['ZREM', `drivers:geo:${city}`, `driver_${uid}`]);
}

async function geoSearchDrivers(city, lng, lat, radiusKm = 5, limit = 20) {
  const redis = getRedis();
  if (!redis) return [];
  const key = `drivers:geo:${city}`;
  // GEORADIUS key lon lat radius km WITHDIST ASC COUNT limit
  const raw = await redis.sendCommand([
    'GEORADIUS', key, lng, lat, radiusKm, 'km',
    'WITHDIST', 'ASC', 'COUNT', String(limit)
  ]);
  // raw = [[member, distance], ...]
  return (raw || []).map(([member, dist]) => ({
    uid: member.replace(/^driver_/, ''),
    distance: parseFloat(dist),
  }));
}
```

### 4.2 Endpoint matching (baru)

```
GET /api/match/drivers?lat={pickupLat}&lng={pickupLng}&city={city}&radius=5&limit=20
```

- Response: `{ drivers: [{ uid, distance, ... }] }`
- Auth: bisa public (untuk penumpang cek ketersediaan) atau internal

### 4.3 Update `POST /api/driver/location`

- Selain `SET driver_status:{uid}`, panggil `GEOADD drivers:geo:{city}`
- City bisa dari body (`city`) atau geocode reverse (opsional, tambahan)

---

## 5. Kota (city)

- **Opsi A:** Driver kirim `city` di body (dari app, pilih kota)
- **Opsi B:** Geocode reverse dari lat/lng → dapat kota (API tambahan)
- **Opsi C:** Satu key global `drivers:geo` jika cakupan masih satu wilayah

Untuk awal: gunakan `city` dari request body, default `default` jika kosong.

---

## 6. Pub/Sub (Opsional)

Untuk notifikasi realtime (order baru ke driver terdekat):

| Channel | Event |
|---------|-------|
| `order:new` | Order baru butuh driver |
| `driver:matched` | Driver dapat order |

```javascript
// Publish
await redis.publish('order:new', JSON.stringify({ orderId, pickupLat, pickupLng, city }));

// Subscribe (worker terpisah)
const subscriber = redis.duplicate();
await subscriber.connect();
await subscriber.subscribe('order:new', (message) => { ... });
```

---

## 7. Migrasi dari driver_status

- `driver_status:{uid}` tetap dipakai untuk metadata (status, route, journey)
- GEO index `drivers:geo:{city}` **tambahan** untuk query jarak
- Saat `POST /driver/location`: tulis ke kedua (SET + GEOADD)
- Saat `DELETE /driver/status`: hapus dari kedua (DEL + ZREM)

---

## 8. Langkah Deploy

1. ~~Pastikan Redis 6.2+ (GEO sudah ada di Redis 3.2+)~~
2. ~~Tambah helper GEO di `redis.js`~~ ✅
3. ~~Update `POST /driver/location` → GEOADD~~ ✅
4. ~~Update `DELETE /driver/status` → ZREM~~ ✅
5. ~~Buat route `GET /api/match/drivers`~~ ✅
6. ~~Flutter kirim `city`~~ ✅ (Tahap 1: dari reverse geocode subAdministrativeArea)
7. ~~Validasi response matching~~ ✅ (Tahap 1: filter status siap_kerja, punya route)
8. ~~Integrasi di Flutter penumpang~~ ✅ (Tahap 2: getMatchDrivers → getActiveDriversForMap, fallback ke getDriverStatusList)
9. ~~Filter kapasitas di backend~~ ✅ (Tahap 4.2: minCapacity query, maxPassengers di driver_status)
10. ~~Skor matching opsional~~ ✅ `GET /api/match/drivers?destLat=&destLng=` → urutan `matchScore` (jarak + arah ke tujuan + kapasitas + fresh `lastUpdated`)
11. ~~Pub/Sub lokasi~~ ✅ Opsional: `REDIS_PUBLISH_DRIVER_LOCATION=1` → channel `driver:location` (lihat `REALTIME_DRIVER_UPDATES.md`)

---

## 9. Referensi

- [Redis GEO](https://redis.io/commands/geoadd/)
- [Redis Node client – geoAdd](https://github.com/redis/node-redis/blob/master/docs/commands/geoAdd.md)
- `docs/SETUP_REDIS_PRODUCTION.md` – skala & alert
