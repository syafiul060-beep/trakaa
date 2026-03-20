# Realtime update lokasi driver (Redis Pub/Sub)

## Ringkasan

Setelah `POST /api/driver/location` berhasil, API dapat **mempublish** event ke Redis channel `driver:location` agar worker atau layanan WebSocket subscribe dan mendorong update ke app penumpang.

## Aktivasi

Set environment di server:

```bash
REDIS_PUBLISH_DRIVER_LOCATION=1
```

Tanpa variabel ini, tidak ada publish (hemat perintah Redis).

## Payload (JSON)

```json
{
  "uid": "driverFirebaseUid",
  "city": "default",
  "lat": -3.32,
  "lng": 114.59,
  "ts": 1710000000000
}
```

## Langkah berikutnya (produksi)

1. Proses terpisah (worker) `SUBSCRIBE driver:location` lalu broadcast ke **Socket.IO** / **WebSocket** per grid geografis.
2. App penumpang: subscribe room grid dari posisi user; throttle render (mis. 80–120 ms) + batasi jumlah marker.
3. Jangan kirim API key atau JWT di channel publik; hanya id driver + koordinat + timestamp.

Lihat juga `REDIS_GEO_MATCHING.md` dan `SETUP_REDIS_PRODUCTION.md`.
