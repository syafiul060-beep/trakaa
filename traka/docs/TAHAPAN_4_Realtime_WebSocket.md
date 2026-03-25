# Tahap 4 — Realtime massal (Redis → worker → WebSocket → klien)

Dokumen ini melengkapi [`TAHAPAN_MIGRASI_INFRA_4_FASE.md`](TAHAPAN_MIGRASI_INFRA_4_FASE.md) bagian **Tahap 4**.

**Prasyarat:** [Tahap 1](../traka-api/docs/TAHAPAN_1_OBSERVABILITAS.md) + [Tahap 2](TAHAPAN_2_Optimasi_Murah.md) + [Tahap 3](TAHAPAN_3_Scale_API_Redis_Hybrid.md) stabil (API + Redis + hybrid teruji).

**Peringatan ruang lingkup:** Tahap 4 **bukan** satu klik di Firebase — ini **proyek engineering** (service baru + klien Flutter + auth + operasi). Kerjakan **bertahap** (worker dulu, lalu WS, lalu app), dengan **fallback** ke perilaku saat ini sampai stabil.

---

## Tujuan

- Posisi driver sampai ke penumpang **tanpa** bergantung pada polling/listener Firestore yang berat untuk **setiap** update.
- Alur data: **`POST /api/driver/location`** → Redis **`PUBLISH`** channel `driver:location` → **worker** subscribe → **WebSocket** (`wss://`) → app penumpang join **room** (grid/geohash).
- Throttle render di klien (mis. 80–120 ms) + batas marker — selaras [`TAHAPAN_2_Optimasi_Murah.md`](TAHAPAN_2_Optimasi_Murah.md).

---

## Yang sudah ada di repo (API)

| Bagian | Status |
|--------|--------|
| Publish ke Redis | Jika `REDIS_PUBLISH_DRIVER_LOCATION=1`, setelah lokasi tersimpan, API memanggil `redis.publish('driver:location', JSON…)` — lihat `traka-api/src/routes/driver.js`. |
| Payload | `uid`, `city`, `lat`, `lng`, `ts` — [`../traka-api/docs/REALTIME_DRIVER_UPDATES.md`](../traka-api/docs/REALTIME_DRIVER_UPDATES.md). |
| Tanpa env | Tidak ada publish (hemat Redis). |

**Yang belum ada (umumnya):** proses Node terpisah yang `SUBSCRIBE driver:location`, server WebSocket/Socket.IO, dan kode Flutter yang `connect` + `join` room — itu pekerjaan Tahap 4.

---

## Keputusan stack — mana yang “terbaik” untuk Traka?

Ini rekomendasi **praktis** (bukan satu-satunya benar). Tujuannya: **cepat stabil di produksi** + **mudah scale** + **kurangi kode custom**.

### Socket.IO vs `ws` (plain WebSocket)

| | **Socket.IO** (disarankan) | **`ws` + custom** |
|---|---------------------------|-------------------|
| **Kelebihan** | Room/join bawaan, reconnect, heartbeat; **@socket.io/redis-adapter** untuk banyak instance; klien Flutter `socket_io_client` matang | Dependensi minimal, kontrol penuh protokol |
| **Kekurangan** | Protokol sedikit lebih berat; server harus kompatibel Socket.IO | Anda yang tulis: reconnect, room, multi-node, versi protokol |

**Rekomendasi:** **Socket.IO** untuk service realtime Traka — terutama jika nanti ada **lebih dari satu** proses WS (Railway scale). Plain `ws` baru masuk akal jika tim sangat ingin footprint kecil **dan** bersedia investasi waktu di semua edge case.

### Room = geohash berapa digit?

Geohash memendekkan `lat,lng` menjadi string; digit lebih panjang = kotak lebih kecil.

| Precision | Kira-kira ukuran kotak* | Kapan dipakai |
|-----------|-------------------------|---------------|
| **5** | ~±2,4 km | **MVP / default:** satu room per cell, broadcast tidak terlalu sering pindah saat penumpang jalan |
| **6** | ~±0,6 km | Area padat; lebih relevan per titik, tapi **lebih sering** ganti room saat peta digeser |
| **7** | ~±0,15 km | Hanya jika benar-benar perlu; biaya join/leave room naik |

\*Perkiraan; tergantung lintang.

**Rekomendasi:** mulai **precision 5** sebagai nama room (mis. `gh5:gbz80`). Untuk menghindari driver “di tepi sel” tidak terlihat, penumpang bisa subscribe **9 sel** (sel tengah + 8 tetangga) atau server broadcast ke tetangga — pilih satu strategi dan dokumentasikan.

**Auth ticket dari REST**

**Rekomendasi:** endpoint **`POST /api/.../realtime-ticket`** (atau nama serupa) yang:

1. Memverifikasi **Firebase ID token** (sama seperti API lain).
2. Mengembalikan **ticket sekali pakai / JWT singkat** (TTL 60–120 detik) yang hanya berisi klaim minimal (`sub`, `role`, mungkin `city`).
3. Koneksi Socket.IO memakai `auth: { token: ticket }` (atau query terpisah **hanya untuk handshake** — jangan log panjang).

Worker **tidak** mempercayai payload Redis untuk auth — Redis hanya membawa `uid` + koordinat; siapa boleh join room dicek saat handshake.

### Ringkasan pilihan default

1. **Socket.IO** + **Redis adapter** saat scale horizontal.  
2. **Room geohash precision 5** (+ strategi tetangga jika perlu).  
3. **Ticket REST** (Firebase → ticket pendek → connect WS).  
4. **Flutter:** `socket_io_client` + **flag** `TRAKA_ENABLE_MAP_WS` (atau serupa) + **fallback** hybrid/Firestore.

---

## Rencana engineering (urutan disarankan)

### Fase 4A — Worker + broadcast (tanpa app produksi)

1. Buat repo atau folder `traka-realtime-worker` (contoh): Node + `ioredis` **subscribe** `driver:location`.
2. Hubungkan ke **Socket.IO** (atau `ws`) — broadcast ke room berdasarkan **geohash** / grid dari `lat,lng` payload.
3. Deploy ke **staging** (Railway service kedua atau VPS), **`wss://`** lewat reverse proxy.
4. Uji dengan klien uji (bukan Flutter dulu): skrip Node atau Postman WebSocket — pastikan event sampai.

### Fase 4B — Auth WebSocket

- Jangan kirim JWT penuh di channel Redis publik.
- **Di repo:** `POST /api/realtime/ws-ticket` (Bearer Firebase) → `{ ticket, expiresIn }`. Set **`REALTIME_WS_TICKET_SECRET`** (≥16 karakter) **sama** di **traka-api** dan **traka-realtime-worker**. Flutter memanggil endpoint ini jika `TRAKA_REALTIME_SOCKET_TOKEN` kosong.
- Dev: `SOCKET_AUTH_DEV_SECRET` di worker + `TRAKA_REALTIME_SOCKET_TOKEN` di build.

### Fase 4C — Flutter penumpang

- Paket: `socket_io_client` atau `web_socket_channel` — sesuai stack server.
- Saat peta aktif: connect `wss://`, subscribe room dari posisi penumpang; gabungkan update ke state marker yang sudah ada (throttle).
- **Fallback:** jika WS gagal → tetap pakai jalur **hybrid/Firestore** yang sudah ada (jangan hapus dulu).

### Fase 4D — Produksi

1. Set `REDIS_PUBLISH_DRIVER_LOCATION=1` di API **setelah** worker hidup (idealnya worker dulu, lalu publish — lihat [`REALTIME_DRIVER_UPDATES.md`](../traka-api/docs/REALTIME_DRIVER_UPDATES.md)).
2. Rollout app **bertahap**; pantau Redis memory, koneksi WS, Sentry.
3. **Scale:** beberapa instance WS → **Redis adapter** Socket.IO atau sticky session — lihat diskusi di [`TAHAPAN_MIGRASI_INFRA_4_FASE.md`](TAHAPAN_MIGRASI_INFRA_4_FASE.md).

---

## Yang Anda lakukan secara manual (operasi)

| Item | Keterangan |
|------|------------|
| DNS + TLS | Domain untuk `wss://` (sertifikat valid, mis. Let’s Encrypt). |
| Service kedua di Railway / VPS | Worker + WS terpisah dari API REST *atau* sama mesin dengan port berbeda + proxy. |
| Env API | `REDIS_PUBLISH_DRIVER_LOCATION=1` hanya saat worker siap. |
| Firewall | Buka 443; batasi akses Redis tetap privat. |
| Monitoring | Error rate WS, reconnect, latency; alert seperti Tahap 1. |
| QA | Jaringan lemah, background app, baterai — [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md) + skenario peta live. |

**Jangan** deploy App Engine hanya untuk “punya WS” jika stack Anda sudah di Railway — pilih **satu** pola hosting yang jelas.

---

## Urutan berikutnya (setelah `publish-test` & `/health` lokal OK)

Kerjakan **berurutan** — jangan loncat ke Flutter sebelum 1–2 stabil.

| Urutan | Apa | Mengapa |
|--------|-----|---------|
| **1** | **Deploy `traka-realtime-worker` ke Railway** (service baru, root folder worker, `npm start`, env `REDIS_URL` sama dengan API, `PORT` otomatis, `ALLOWED_ORIGINS`) | Worker harus **online** di internet (`wss://` nanti) sebelum app mengandalkan WS. |
| **2** | Di service **traka-api** (Railway), set **`REDIS_PUBLISH_DRIVER_LOCATION=1`** — idealnya **staging** dulu; redeploy | API mulai **publish** ke channel yang sama; worker cloud (atau lokal saat tes) menerima event dari driver sungguhan. |
| **3** | **Flutter:** `socket_io_client`, URL worker (Railway), `join` geohash, throttle marker, **flag** + **fallback** hybrid/Firestore | Pengguna dapat update live; jika WS putus, app tidak “mati”. |

Detail deploy worker: [`../traka-realtime-worker/README.md`](../traka-realtime-worker/README.md).

---

## Gate Tahap 4 selesai

- [ ] Worker subscribe + WS **staging** menerima event dari driver test (publish aktif).
- [ ] `wss://` + model **auth** tidak membocorkan secret di Redis publik.
- [ ] App penumpang **beta** dengan WS + **fallback** lama teruji.
- [ ] Beban tiruan atau traffic beta **tanpa** incident kritis; rollback ke mode non-WS teruji.

**Setelah gate:** operasikan produksi bertahap; dokumentasi runbook untuk on-call.

---

## Dokumen terkait

- [`../traka-api/docs/REALTIME_DRIVER_UPDATES.md`](../traka-api/docs/REALTIME_DRIVER_UPDATES.md)  
- [`../traka-api/docs/REDIS_GEO_MATCHING.md`](../traka-api/docs/REDIS_GEO_MATCHING.md)  
- [`../traka-api/docs/SETUP_REDIS_PRODUCTION.md`](../traka-api/docs/SETUP_REDIS_PRODUCTION.md)

*Tahap 4 sering memakan beberapa sprint — pecah PR per fase di atas.*

## Skeleton di repo

Folder **[`../../traka-realtime-worker/`](../../traka-realtime-worker/)** — Node + Socket.IO + `ioredis` subscribe `driver:location` + room `gh5:*` (precision 5). Lihat `README.md` di sana untuk menjalankan lokal dan deploy.

**Flutter (penumpang, peta Cari Travel):** dependensi `socket_io_client`; konfigurasi [`lib/config/traka_realtime_config.dart`](../lib/config/traka_realtime_config.dart) (`TRAKA_ENABLE_MAP_WS`, `TRAKA_REALTIME_WS_URL`, opsional `TRAKA_REALTIME_SOCKET_TOKEN`); service [`lib/services/passenger_map_realtime_socket.dart`](../lib/services/passenger_map_realtime_socket.dart); integrasi di [`lib/screens/penumpang_screen.dart`](../lib/screens/penumpang_screen.dart) dengan fallback ke stream hybrid/Firestore. Build hybrid + WS: `.\scripts\build_hybrid.ps1 -EnableMapWs -RealtimeWsUrl "https://<worker>.up.railway.app"`.

**Auth produksi (ticket REST)** ke handshake Socket.IO masih langkah berikutnya jika worker memakai secret selain dev.
