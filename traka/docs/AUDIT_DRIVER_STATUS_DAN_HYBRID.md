# Audit: tulis `driver_status`, lokasi hybrid, dan skenario uji hybrid penuh

Dokumen ini merangkum **kapan dan seberapa sering** klien menulis `driver_status/{uid}` (dan panggilan API terkait), serta **alur QA hybrid** end-to-end yang selaras dengan [`QA_HYBRID_REGRESI.md`](QA_HYBRID_REGRESI.md).

---

## 1. Ringkasan eksekutif

| Aspek | Ringkas |
|--------|---------|
| **Dual-write hybrid** | Jika `TrakaApiConfig.isApiEnabled`: `POST /api/driver/location` (Redis GEO + publish) **lalu** `Firestore driver_status.set(merge: true)` dengan koordinat **GPS perangkat** (bukan snap Roads di server). |
| **Frekuensi lokasi** | Ditentukan **gate** di `DriverScreen._shouldUpdateFirestore` + konstanta `DriverStatusService` — bukan interval tetap murni. |
| **Batas server** | Rate limit per UID: default **120 req/menit** (env `DRIVER_LOCATION_RATE_LIMIT_PER_MIN`, rentang 30–600) — lihat `traka-api/src/routes/driver.js`. |
| **Tambahan tulis** | `updateCurrentPassengerCount` → `PATCH /api/driver/status` + Firestore merge; `removeDriverStatus` → `DELETE /api/driver/status` + hapus doc Firestore. |
| **Uji regresi** | Tabel lengkap ada di `QA_HYBRID_REGRESI.md`; §5 = **alur urut** satu sesi; §3.1 = lembar angka nyata; §6 = Map WS. |
| **Map WS (opsional)** | Jika `TRAKA_ENABLE_MAP_WS` + URL worker: penumpang di peta Cari Travel pakai Socket.IO (`driver:location`), bukan `GET …/status` tiap ~3 dtk per driver. |

---

## 2. Jalur tulis ke `driver_status` dan API

### 2.1 `DriverStatusService.updateDriverStatus`

- **Hybrid:** `TrakaApiService.postDriverLocation(...)` kemudian `driver_status/{uid}.set(data, merge: true)`.
- **Non-hybrid:** hanya Firestore `set(merge: true)`.
- **Pemanggil utama:** `DriverScreen._updateDriverStatusToFirestore` (setelah gate jarak/waktu), plus **langsung** `updateDriverStatus` saat auto-switch rute alternatif (`_checkAndAutoSwitchRoute`).

### 2.2 `DriverStatusService.updateCurrentPassengerCount`

- **Hybrid:** `PATCH /api/driver/status` (`currentPassengerCount`) lalu Firestore merge field yang sama.
- **Pemanggil:** `data_order_driver_screen.dart` saat hitungan slot penumpang berubah.

### 2.3 `DriverStatusService.removeDriverStatus`

- **Hybrid:** `DELETE /api/driver/status` lalu hapus dokumen Firestore.
- **Pemanggil:** mis. logout / akun (`profile_driver_screen`, `profile_penumpang_screen`), dan alur selesai di `driver_screen` (lihat grep di repo).

### 2.4 Gate lokasi di beranda driver

Hanya jika `_isDriverWorking` **dan** `_shouldUpdateFirestore(position)` benar, alur GPS memanggil `_updateDriverStatusToFirestore` (tanpa `await` agar tidak memblok interpolasi/kamera):

```3468:3476:traka/lib/screens/driver_screen.dart
    // Update status & lokasi ke Firestore agar penumpang bisa menemukan driver.
    // Saat menuju jemput: update sering (50m/5s) untuk Lacak Driver.
    // Saat rute biasa: update hemat (2km/15min).
    // Jangan await di sini: POST hybrid + Roads di server bisa lambat → memblokir
    // interpolasi & kamera; ikon tertinggal km dan UI terasa macet.
    if (_isDriverWorking &&
        (_lastUpdatedTime == null || _shouldUpdateFirestore(position))) {
      unawaited(_updateDriverStatusToFirestore(position));
    }
```

Mode gate (`_shouldUpdateFirestore`):

| Mode | Kondisi (ringkas) | Ambang jarak | Ambang waktu |
|------|-------------------|--------------|--------------|
| **Live tracking** | `_navigatingToOrderId != null` **atau** `_jumlahPenumpangPickedUp > 0` **atau** `_jumlahBarang > 0` | ≥ **50 m** | ≥ **5 dtk** |
| **Pickup proximity** | `_waitingPassengerCount > 0` (agreed menunggu jemput, belum live penuh) | ≥ **300 m** | ≥ **60 dtk** |
| **Default** | Siap kerja tanpa kondisi di atas | ≥ **2 km** | ≥ **15 menit** |

Konstanta sumber: `DriverStatusService` (`minDistance*`, `maxMinutesForceUpdate`, `maxSecondsLiveTracking`, `maxSecondsPickupProximity`).

### 2.5 Timer + stream GPS (konteks frekuensi *percobaan* update)

- Saat **nav aktif** (`_isDriverWorking || _navigatingToOrderId != null`): stream posisi frekuensi tinggi + timer **8 dtk** (fallback `getCurrentPosition` jika stream “diam” > ~14 dtk).
- Saat **tidak** nav aktif: timer **15 dtk** memanggil `_getCurrentLocation(forTracking: true)`.

Timer **tidak** sama dengan frekuensi write: setiap tick/posisi baru tetap harus lolos gate di §2.4 (kecuali pemanggilan lain yang memaksa satu kali write, mis. mulai/henti kerja).

### 2.6 Peristiwa yang memicu write di luar gate periodik

- **Mulai bekerja:** `_updateDriverStatusToFirestore` sekali setelah state siap (`statusSiapKerja`).
- **Akhiri pekerjaan (`_endWork`):** `_updateDriverStatusToFirestore` → `statusTidakAktif` (merge doc; driver tetap punya dokumen dengan lokasi terakhir).
- **`removeDriverStatus`:** hapus Redis/API + hapus doc Firestore — mis. `driver_screen.dispose`, logout di `profile_driver_screen` / `profile_penumpang_screen` (bukan jalur normal selesai rute saja).
- **Auto-switch rute:** `updateDriverStatus` langsung (melewati `_shouldUpdateFirestore` untuk sinkron index rute).
- **Restore / alur khusus:** grep `updateDriverStatus` / `_updateDriverStatusToFirestore` di `driver_screen.dart` untuk daftar lengkap saat refactor.

---

## 3. Teoritis: beban write vs rate limit

- **Atas batas kasar live tracking:** ~**12** lokasi/menit per driver (5 dtk) **jika** GPS memberi update yang lolos gate setiap 5 dtk — di jalan sunyi bisa lebih jarang karena jarak 50 m.
- **Default siap kerja:** jauh di bawah itu (2 km atau 15 menit).
- **Server:** 120/menit per UID memberi **margin** untuk live tracking + retry singkat; burst + retry 429 bisa memicu Analytics `hybrid_driver_location_rate_limited` (lihat catatan teknis di `QA_HYBRID_REGRESI.md`).

### Apa ini? (baca dulu jika §3 terasa membingungkan)

| Pertanyaan | Jawaban singkat |
|------------|-----------------|
| **Mau diukur apa?** | Berapa kali aplikasi **driver** (mode hybrid) mengirim **`POST …/api/driver/location`** ke server dalam beberapa menit — itu yang bikin beban API dan kena rate limit. |
| **Kenapa repot pakai proxy / HAR?** | Lalu lintas ke API pakai **HTTPS** (terenkripsi). Tanpa “perantara” di tengah, Anda tidak bisa melihat daftar URL dari luar app. **Proxy** = PC Anda jadi perantara sementara; setelah itu Anda bisa **simpan rekaman** ke file **HAR** (format standar daftar request). |
| **HAR itu apa?** | Satu file JSON berisi jejak request (waktu, URL, metode POST/GET, dll.). Bisa diekspor dari mitmproxy, Charles, Fiddler, atau Android Studio. |
| **Skrip `count_har_…` ngapain?** | Membuka file HAR, **menghitung** saja: ada berapa `POST` ke `…/api/driver/location`, per menit berapa, puncak burst 10 detik berapa — supaya tidak hitung manual. |
| **Wajib?** | **Tidak.** Dokumen audit (§1–2) sudah menjelaskan *kapan* app boleh kirim lokasi. §3.1–3.3 hanya untuk **membuktikan dengan angka** di staging sebelum rilis atau saat curiga terlalu sering kirim. |
| **Alternatif paling gampang?** | Punya akses **log server** (Railway, dll.): hitung baris `POST` lokasi per UID di periode yang sama — sama tujuannya, beda alat. |

### 3.1 Lembar pengukuran sesi (isi manual — staging / produksi)

Salin tabel ke issue rilis atau spreadsheet; satu baris = satu kombinasi **build + API URL + UID driver uji**.

| Field | Nilai (isi saat uji) |
|--------|----------------------|
| **Tanggal / TZ** | |
| **Build** | version + `TRAKA_USE_HYBRID` + Map WS on/off |
| **`TRAKA_API_BASE_URL`** | |
| **`DRIVER_LOCATION_RATE_LIMIT_PER_MIN` (server)** | |
| **Skenario** | ☐ Default siap kerja (jalan) ☐ Live tracking (nav jemput / picked up / barang) ☐ Campuran |
| **Durasi sampel** | mis. 10 menit |
| **POST `/api/driver/location` — total** | _N_ |
| **Per menit (rata-rata)** | _N / menit_ |
| **Puncak burst (req / 10 dtk)** | |
| **HTTP 429** | ☐ Tidak ☐ Ya — berapa kali |
| **PATCH `/api/driver/status`** (sesi sama) | |
| **DELETE `/api/driver/status`** | |
| **Catatan** | perangkat, jaringan, mock GPS, retry |

**Contoh interpretasi (bukan pengukuran nyata):** driver live tracking teoritis ≤ ~12 POST/menit; jika sampel menunjuk **>100/menit** untuk satu UID, cari pemanggilan ganda atau gate yang bocor.

### 3.2 Metodologi pengukuran (pilih satu atau gabung)

1. **Proxy HTTP (disarankan untuk angka pasti)**  
   Pasang mitmproxy / Charles / Fiddler di PC, hubungkan perangkat uji; filter host = base URL API; hitung **`POST …/api/driver/location`** dalam jendela waktu. Sertakan **Authorization** (token pendek) jangan di-log publik.

2. **Android Studio Network Inspector**  
   Filter path `driver/location`; ekspor HAR bila perlu dan hitung di luar IDE.

3. **Sisi server (jika akses log)**  
   Hitung baris log `POST /driver/location` per UID di Railway/log drain; selaraskan timezone dengan sesi app.

4. **Firebase Analytics**  
   Event **`hybrid_driver_location_rate_limited`** = respons **429** pada POST lokasi (bukan pengganti hitung POST, tapi sinyal overload).

5. **Firestore (bandingkan)**  
   Field `lastUpdated` pada `driver_status/{uid}` berubah setiap kali klien lolos gate; frekuensi tidak sama dengan POST jika POST gagal tapi Firestore tetap ditulis — bandingkan dengan proxy untuk audit dual-write.

### 3.3 Langkah praktis: export HAR → isi §3.1

**Urutan logika:** HP Android → internetnya **dialihkan lewat PC** (proxy) → PC bisa merekam request → simpan sebagai **HAR** → jalankan **skrip hitung** → tulis angka di tabel §3.1.

1. **Pasang proxy di PC** (mitmproxy / Charles / Fiddler). Di Android: Wi‑Fi yang sama dengan PC → set **proxy manual** = **IP PC** (mis. `192.168.1.5`) + **port** (mitmproxy biasanya `8080`). Lalu di HP **pasang sertifikat CA** dari mitm (Pengaturan → Keamanan → sertifikat pengguna) supaya **HTTPS** bisa direkam; tanpa ini daftar request akan kosong atau “broken”.
2. **Jalankan app hybrid** di HP: login **driver**, **Siap kerja** sesuai skenario (jalan biasa vs navigasi jemput), biarkan **±10 menit**.
3. **Export HAR** dari tool (contoh: Android Studio **App Inspection → Network Inspector** sambil app jalan, lalu export; atau dari Charles / mitmproxy **Save / Export HAR**).
4. **Hitung otomatis** (pilih salah satu):
   - **Node** (umumnya sudah ada di mesin dev):  
     `node traka/scripts/count_har_driver_location.mjs path\ke\session.har --patch --delete`  
     Opsional: `--verbose` untuk daftar URL per waktu.
   - **PowerShell 7+**:  
     `pwsh traka/scripts/count_har_driver_location.ps1 -Path path\ke\session.har -IncludePatchStatus -IncludeDeleteStatus`  
     Jika `pwsh` tidak ada: [instal PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows) atau pakai perintah Node di atas.
5. **Salin angka** ke kolom §3.1 (total POST, rata-rata/menit, burst, 429 manual dari kolom status di proxy bila perlu).

**Privasi:** HAR berisi header `Authorization` — jangan commit ke git / jangan lampirkan publik; simpan lokal atau redaksi.

---

## 4. Risiko & mitigasi

| Risiko | Mitigasi / pantauan |
|--------|----------------------|
| **429 lokasi** | Tune `DRIVER_LOCATION_RATE_LIMIT_PER_MIN`; pantau Analytics 429 + breadcrumb API. |
| **Firestore writes** | Tier default/pickup/live sudah mengurangi spam; indeks `driver_status` untuk query penumpang — lihat `firestore.indexes.json` + baris QA tentang fallback limit 400. |
| **Konsistensi Redis vs Firestore** | Redis memakai snap Roads; Firestore menyimpan GPS — disengaja (komentar di `driver_status_service.dart`). |
| **PATCH count vs lokasi** | Perubahan daftar order meng-update count tanpa memicu full location POST setiap kali — pisahkan beban. |

---

## 5. Skenario uji hybrid **penuh** (satu sesi berurutan)

Lakukan setelah **Smoke API** + **Prasyarat** di `QA_HYBRID_REGRESI.md` PASS. Angka **#x.y** mengacu ke baris tabel di dokumen itu (isi Pass/Fail di sana).

1. **Deploy & kesehatan API** — `#` smoke: health, TLS, admin opsional.
2. **Penumpang: order travel** — **1.1**, **1.4** (kirim barang hybrid jika relevan), **1.5** (jadwal tanggal WIB).
3. **Driver: Siap kerja + lokasi** — **2.1**, **2.2**, **2.3** (simulasi error API di staging), **2.4**, **2.5** (Directions + putar arah).
4. **Matching & lacak** — pastikan penumpang melihat driver di peta/daftar; lacak driver saat navigasi jemput (live tier).
5. **Jadwal** — **3.1–3.7** (termasuk background recovery **3.2**, pindah jadwal **3.5**, gate tombol Rute **3.7**).
6. **Instruksi bayar driver** — **4.1**.
7. **Admin panel** — **5.1** jika rilis menyertakan admin.
8. **Negatif & regresi** — **6.1–6.7** (banner jemput, double-tap sheet, non-hybrid build).

**Resume / foreground:** setelah langkah panjang, ulangi singkat **3.2** dan skenario “driver minimize ±30 dtk → buka lagi” untuk memastikan `HybridForegroundRecovery` dan stream lokasi tidak meninggalkan state kosong.

**Build dengan Map WS:** centang di **Sesi uji** `QA_HYBRID_REGRESI.md`, lalu jalankan checklist **§6** di bawah dan isi **§3.1** agar beban **POST** driver terpisah dari **GET** polling penumpang.

---

## 6. Map WebSocket (`TRAKA_ENABLE_MAP_WS`)

Hanya relevan jika build memakai hybrid **dan** `dart-define` berikut (lihat `scripts/build_hybrid.ps1` / `run_hybrid.ps1`: `-EnableMapWs -RealtimeWsUrl "https://…"`):

- `TRAKA_ENABLE_MAP_WS=true`
- `TRAKA_REALTIME_WS_URL=<URL worker Socket.IO, HTTPS>`

Opsional: `TRAKA_REALTIME_SOCKET_TOKEN=…` (handshake `auth.token`); jika kosong, app memanggil **`POST /api/realtime/ws-ticket`** (`TrakaApiService.fetchRealtimeMapWsTicket`) — butuh secret yang sama di API + worker (lihat [`TAHAPAN_4_Realtime_WebSocket.md`](TAHAPAN_4_Realtime_WebSocket.md)).

### 6.1 Perilaku di klien

| Tanpa Map WS | Dengan Map WS (`TrakaRealtimeConfig.isEnabled`) |
|--------------|-----------------------------------------------|
| Peta **Cari Travel** (penumpang): per driver, `DriverStatusService.streamDriverStatusData` → **`GET /api/driver/:uid/status` setiap ~3 detik** (`TrakaApiService.streamDriverStatus`) | **Tidak** memasang stream polling per driver di setup peta; posisi live lewat **Socket.IO** event `driver:location` |
| Beban penumpang naik linear dengan jumlah marker | Satu koneksi WS + join room; update mengikuti publish Redis → worker |

Implementasi: `lib/services/passenger_map_realtime_socket.dart` (`join` / `leave`, event `driver:location`); integrasi `penumpang_screen.dart` (`_maybeStartPassengerMapRealtimeSocket`, `_onRealtimeDriverLocation`). Saat penumpang berpindah **> ~800 m**, `updatePassengerPosition` meng-emit join ulang agar room geohash tetap relevan.

**Penting:** POST lokasi driver **tetap** dari app driver (§2); Map WS mengubah cara **penumpang** menerima update, bukan frekuensi tulis driver.

### 6.2 Prasyarat infrastruktur

- API: `REDIS_PUBLISH_DRIVER_LOCATION=1` agar lokasi dipublish ke channel yang di-subscribe worker (lihat [`../traka-api/docs/REALTIME_DRIVER_UPDATES.md`](../traka-api/docs/REALTIME_DRIVER_UPDATES.md)).
- Worker Socket.IO harus jalan di URL yang sama dengan `TRAKA_REALTIME_WS_URL`.

### 6.3 Checklist QA cepat (Map WS on)

| # | Cek | Diharapkan |
|---|-----|------------|
| WS-1 | Penumpang: buka peta Cari Travel dengan ≥1 driver hybrid | Marker bergerak; di debug console: log “Socket.IO ON … polling OFF”. |
| WS-2 | Matikan worker / salah URL | Tidak freeze; degradasi/reconnect sesuai kode. |
| WS-3 | Banyak driver di viewport | UI tetap responsif (throttle render — lihat Tahap 2/4). |
| WS-4 | Proxy: hitung `GET …/driver/{uid}/status` saat WS on | Frekuensi polling per driver **berkurang** vs WS off untuk peta yang sama. |

---

## 7. Referensi file

| File | Peran |
|------|--------|
| `lib/services/driver_status_service.dart` | Konstanta gate, `updateDriverStatus`, `updateCurrentPassengerCount`, `removeDriverStatus`, restore rute |
| `lib/services/traka_api_service.dart` | `postDriverLocation`, `patchDriverStatus`, `deleteDriverStatus`, `getDriverStatus` |
| `lib/screens/driver_screen.dart` | Timer/stream GPS, `_shouldUpdateFirestore`, `_updateDriverStatusToFirestore` |
| `lib/screens/data_order_driver_screen.dart` | `updateCurrentPassengerCount` |
| `traka-api/src/routes/driver.js` | Rate limit, `POST /location`, Redis GEO |
| `docs/QA_HYBRID_REGRESI.md` | Tabel regresi + observabilitas `[DriverHybrid]` / `[Field]` |
| `docs/FIELD_OBSERVABILITY.md` | Matriks breadcrumb lapangan |
| `docs/TAHAPAN_4_Realtime_WebSocket.md` | Arsitektur Redis → worker → WS |
| `lib/config/traka_realtime_config.dart` | Flag Map WS + URL + token |
| `lib/services/passenger_map_realtime_socket.dart` | Socket.IO penumpang |
| `scripts/build_hybrid.ps1`, `scripts/run_hybrid.ps1` | `-EnableMapWs`, `TRAKA_REALTIME_WS_URL` |

---

*Terakhir diselaraskan dengan codebase pada audit internal; isi §3.1 setelah setiap sesi pengukuran; jika perilaku klien/API berubah, perbarui §2–3, §6–7, dan tautan baris kode.*
