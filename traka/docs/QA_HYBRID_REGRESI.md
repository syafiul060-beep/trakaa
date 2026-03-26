# QA regresi mode hybrid

Dokumen ini untuk uji cepat sebelum rilis ketika app dibuild dengan **`TRAKA_USE_HYBRID=true`** + **`TRAKA_API_BASE_URL`** (lihat `scripts/build_hybrid.ps1`). Tanpa itu, banyak fitur API tidak jalan — itu bukan bug, melainkan mode “Firestore-only”.

**Prioritas operasional & skala:** urutan “mulai dari sini” (isi **Sesi uji** → smoke API → skenario penuh) ada di [`KESIAPAN_SKALA_JUTAAN_PENGGUNA.md`](KESIAPAN_SKALA_JUTAAN_PENGGUNA.md#fokus-operasional-mulai-dari-sini).

---

## Sesi uji (isi sebelum mulai)

| Field | Nilai |
|-------|--------|
| **Tanggal** | _YYYY-MM-DD_ |
| **Tester** | _nama_ |
| **Lingkungan** | ☐ Staging &nbsp; ☐ Production &nbsp; ☐ Lain: _______ |
| **`TRAKA_API_BASE_URL`** (yang dipakai build) | https://trakaa-production.up.railway.app |
| **Build app** (version + build / CI #) | _mis. 1.4.0 (210) atau #456_ |
| **Define opsional** (centang jika dipakai di build ini) | ☐ `TRAKA_CREATE_ORDER_VIA_API` ☐ `TRAKA_API_CERT_SHA256` ☐ Map WS (`TRAKA_ENABLE_MAP_WS` + URL) |
| **Firebase project** (jika relevan) | _default / alias_ |
| **Commit / tag API** (server yang dilayani oleh URL di atas) | _mis. `main` @ abc1234_ |
| **Layanan backend** (cek cepat) | ☐ Postgres order aktif ☐ Redis driver ☐ WebSocket map (jika dipakai) |

_Isi **Pass/Fail** di tabel dengan `PASS` / `FAIL` / `N/A`. **Catatan** untuk nomor issue, screenshot, atau perangkat._

**Arsip rilis:** Simpan salinan baris **Sesi uji** + **Ringkasan** (copy ke issue release / Notion) agar setiap build bisa dilacak tanpa tebak-tebak URL atau commit.

---

## Smoke API pasca-deploy (~5 menit)

Jika driver massal uji **Siap kerja**: API membatasi `POST /api/driver/location` per **UID** (default ±120/menit, env `DRIVER_LOCATION_RATE_LIMIT_PER_MIN`). **429** = penyesuaian load test, bukan bug app. Set env di Railway: [`../traka-api/docs/RAILWAY_DEPLOY_CEPAT.md`](../traka-api/docs/RAILWAY_DEPLOY_CEPAT.md).

Langkah singkat **setelah** API di-deploy (sebelum / bersamaan dengan QA app):

1. **Health:** `GET {TRAKA_API_BASE_URL}/health` → respons sukses (bukan 5xx / timeout).
2. **TLS / URL:** Pastikan URL sama persis dengan yang di-embed build (scheme `https`, tanpa trailing slash ganda).
3. **Admin / integrasi:** Jika ada kunci ke admin, satu request layar admin ke API env yang sama → tidak 401/CORS salah.

**Contoh perintah health** (ganti `https://api.example.com` dengan **`TRAKA_API_BASE_URL` tanpa trailing slash**):

```bash
# macOS / Linux / Git Bash
curl -sS -D - -o /dev/null "https://api.example.com/health"
# atau lihat body + status:
curl -sS "https://api.example.com/health"
```

```powershell
# Windows PowerShell (curl = curl.exe)
curl.exe -sS "https://api.example.com/health"
# alternatif native:
Invoke-WebRequest -Uri "https://api.example.com/health" -UseBasicParsing | Select-Object StatusCode, Content
```

**Debug Postgres (hanya staging / lingkungan terpercaya):** `GET /health?debug=1` menambah field diagnostik (`pgError`, dll.) saat query DB gagal. Jangan dipakai di production publik — pesan error bisa membocorkan detail internal.

```bash
curl -sS "https://api.example.com/health?debug=1"
```

```powershell
curl.exe -sS "https://api.example.com/health?debug=1"
```

Diharapkan: **HTTP 200** dan JSON seperti `{"ok":true,"status":"traka-api","checks":{...}}` (lihat handler `/health` di API). **503** + `"ok":false` biasanya Redis/dependency — hybrid driver ikut terdampak; tetap catat di release. Timeout atau `Could not resolve host` = gagal langkah 1.

Jika langkah 1 gagal, uji app hybrid akan mengecewakan — perbaiki deploy dulu, baru lanjut tabel di bawah.

---

## Prasyarat

- [ ] Smoke **Health** di bagian **Smoke API pasca-deploy** sudah **PASS** (atau dicatat jika hanya retest app).
- [ ] IPA/APK/AAB sesuai baris **Build app** di atas terpasang di perangkat uji.
- [ ] Log cold start menunjukkan hybrid aktif (baris backend di `main.dart`).
- [ ] Akun penumpang + driver uji tersedia di **Firebase / lingkungan** yang sama dengan API.
- [ ] _(Opsional dev)_ Di folder `traka/`: `flutter test test/driver_schedule_prune_test.dart` → semua lulus (regresi logika prune jadwal).

---

## 1. Order + API (penumpang)

| # | Skenario | Langkah / cek | Diharapkan | Pass/Fail | Catatan |
|---|----------|---------------|------------|-----------|---------|
| 1.1 | Buat order travel | Penumpang: cari driver → buat pesanan | Order muncul di Data Order + chat; driver melihat pesanan. | | |
| 1.2 | Buat order (via API) | Hanya jika define **CREATE_ORDER_VIA_API**: buat pesanan baru | Sukses; tidak ada duplikat / order hantu di UI. | | |
| 1.3 | Fallback API | Dev: API tidak terjangkau lalu buat order | Tetap bisa lewat Firestore atau pesan error jelas (sesuai kode). | | |
| 1.4 | Kirim barang + bayar hybrid | Alur ongkos pengirim/penerima sebelum scan | Gate scan / sheet pembayaran sesuai `OrderModel.hybridPay*`. | | |
| 1.5 | **Pesan Travel Terjadwal** — tanggal di form Cari jadwal | Penumpang: buka alur terjadwal → **Ubah tanggal** / form cari rute (bottom sheet) → lihat batas date picker | **Hari pertama** = hari ini menurut **WIB** (bukan kalender timezone perangkat saja). **Hari terakhir** = sama dengan jendela jadwal driver (**7 hari kalender WIB**, `lastScheduleDateInclusiveWib`). Tanggal awal form diklaim ke rentang ini bila dari state lama. | | |

---

## 2. Driver status + matching (Redis / API)

| # | Skenario | Langkah / cek | Diharapkan | Pass/Fail | Catatan |
|---|----------|---------------|------------|-----------|---------|
| 2.1 | Siap kerja | Driver: pilih rute → mulai bekerja | Penumpang di filter/radius melihat driver (path hybrid). | | |
| 2.2 | Update lokasi | Driver bergerak ±2–5 menit | Posisi di peta penumpang terbarui (polling atau WS). | | |
| 2.3 | API error | Hybrid on; respons API gagal (staging) | Tidak crash; degradasi/fallback masuk akal. | | |
| 2.4 | Siap Kerja + pesanan terjadwal sudah agreed (hari yang sama) | Siapkan jadwal hari ini + minimal satu order terjadwal status **agreed** → di beranda tap **Siap Kerja** | Muncul dialog **Pesanan terjadwal**. **Sesuai rute** → rute dimuat lewat jadwal (bukan form bebas). **Tidak** → sheet jenis rute Siap Kerja (manual). | | |
| 2.5 | Rute Directions: Siap Kerja + putar arah | **A)** Siap Kerja: asal nominal jauh dari GPS (akurasi bagus); API pertama kosong lalu retry; hanya satu alternatif. **B)** Lalu **Putar arah** (balik O↔D); ulang skenario A pada rute balik bila perlu. | Garis dari posisi mobil bila memenuhi ambang; snack/teks selaras; retry; satu alternatif = rute sudah dipilih / auto-pilih (**Mulai Rute ini**). | | |

---

## 3. Jadwal driver (Firestore + recovery hybrid)

| # | Skenario | Langkah / cek | Diharapkan | Pass/Fail | Catatan |
|---|----------|---------------|------------|-----------|---------|
| 3.1 | Tambah / edit / hapus | Simpan jadwal | Sheet tutup cepat; snackbar; daftar konsisten; gagal upload → merah + rollback daftar. | | |
| 3.2 | Background recovery | ±5 s background → buka tab Jadwal atau Chat | Data tidak “nyangkut” (HybridForegroundRecovery). | | |
| 3.3 | Sinkron manual | Profil driver → sinkronkan data (jika tersedia) | Jadwal/chat/order terasa segar. | | |
| 3.4 | Simpan berulang cepat | Buka layar Jadwal tunggu load selesai → tambah/edit simpan 2–3× dalam kurang dari ~1 menit | Daftar/snackbar tetap konsisten; tidak “nyangkut”. Saat antre persist aktif: **satu** progress line “Menyimpan…” + FAB Tambah dinonaktifkan sampai giliran selesai. Build dev boleh log `[JadwalLoad] skip deferred cleanup` — perilaku sengaja (kurangi panggilan cleanup berurutan). | | |
| 3.5 | Pindah jadwal | Dari pesanan terjadwal → pindah ke jadwal lain | Sheet memuat daftar target; pindah sukses; kapasitas penuh tetap ditolak dengan snackbar. | | |
| 3.6 | Aktif lewat rute di jadwal | Tap ikon/rute di **Jadwal & Rute** (dengan/tanpa polyline tersimpan; dengan order agreed jika ada) | Rute terikat jadwal (`scheduleId` / alur terjadwal); daftar penumpang menunggu konsisten hari ini; parity Directions seperti **2.5**. | | |
| 3.7 | Tombol **Rute** vs tanggal chip | Buat/simpan jadwal untuk **besok** (atau geser chip ke tanggal lain) lalu lihat kartu jadwal **bukan** hari ini | Tombol **Rute** nonaktif (abu); **tap** → SnackBar penjelasan (bukan hanya tooltip). **Hari ini** + jam belum lewat: aktif. **Hari ini** + jam lewat: nonaktif. Acuan **hari ini** = **WIB** (`DriverScheduleService.todayDateOnlyWib` / `todayYmdWibString`), bukan timezone perangkat. Opsional: uji sekitar **tengah malam WIB** bila kritis. | | |

---

## 4. Instruksi bayar driver (API)

| # | Skenario | Langkah / cek | Diharapkan | Pass/Fail | Catatan |
|---|----------|---------------|------------|-----------|---------|
| 4.1 | Metode bayar | Driver: kelola rekening / QRIS | Dengan hybrid: simpan berhasil; tanpa hybrid: pesan arahkan aktifkan hybrid. | | |

---

## 5. Admin (`traka-admin`)

| # | Skenario | Langkah / cek | Diharapkan | Pass/Fail | Catatan |
|---|----------|---------------|------------|-----------|---------|
| 5.1 | Panggilan API | Buka layar yang memakai `trakaApi` (driver, dll.) | HTTP OK; tidak auth/CORS salah untuk env ini. | | |

**Build admin / env:** _versi commit / URL API admin_

---

## 6. Negatif / regresi cepat

| # | Skenario | Langkah / cek | Diharapkan | Pass/Fail | Catatan |
|---|----------|---------------|------------|-----------|---------|
| 6.1 | Non-hybrid | Install build **tanpa** hybrid | Travel + chat + order utama tetap jalan. | | |
| 6.2 | Notifikasi | Satu transisi order penting | Tidak spam ganda (API + FCM) yang membingungkan. | | |
| 6.3 | Track / link | Buka link lacak hosting | Selaras aturan Firestore / share link. | | |
| 6.4 | Edge: Tidak (Siap Kerja) saat sudah agreed | Ulangi **2.4** → pilih **Tidak** → isi rute manual yang **berbeda** dari jadwal | Tidak crash; catat apakah produk masih mengizinkan (bisa tim review); order agreed tetap terlihat di Data Order sesuai desain. | | |

---

## Ringkasan sesi

| | |
|--|--|
| **Total FAIL** | _isi_ |
| **Blocker rilis?** | ☐ Tidak &nbsp; ☐ Ya — jelaskan di Catatan lingkungan |
| **Tindak lanjut** | _PR / hotfix / retest build ___ |

---

## Catatan teknis

- Crashlytics: breadcrumb `[DriverHybrid]` untuk operasi jadwal di lapangan.
- Setelah **load penuh** jadwal (+ `cleanupPastSchedules`), app menunda **cleanup tunda** pasca-simpan jika pemanggilan cleanup sukses terakhir masih dalam jendela singkat (~2 menit) — mengurangi GET/query order berulang; tidak mengubah data yang disimpan. Saat dilewati, Crashlytics mencatat breadcrumb `[DriverHybrid] schedule.cleanup.skip_deferred …`.
- Sheet **pindah jadwal**: baca `driver_schedules` memakai **satu retry** (~480 ms) jika timeout; setelah retry, **timeout** → breadcrumb `[DriverHybrid] jadwal.pindah.targets.timeout_after_retry`; error lain → non-fatal `jadwal.pindah.targets` (daftar target kosong).
- **Regresi otomatis:** `flutter analyze --no-fatal-infos` + kumpulan `flutter test` ringan — lihat **Traka CI** (`.github/workflows/traka_ci.yml`, termasuk `test/order_service_test.dart`). Lokal cepat prune saja: `flutter test test/driver_schedule_prune_test.dart`.
- **Gate rute jadwal (beranda):** Saat membuka rute dari tab Jadwal, `scheduleId` dicek ke **`todayYmdWibString`**; tanggal di ID tidak cocok → SnackBar (antisipasi pemanggilan dari luar tombol). ID tidak terparse → perilaku lama (boleh lanjut).
- **Query order aktif per driver:** `OrderService.activeScheduleIdsForDriverOrders` memakai **cache dalam memori ±12 detik** per `driverUid` agar panggilan berdekatan (mis. cleanup jadwal) tidak menggandakan query Firestore; data order bisa tertinggal sangat singkat di edge teoretis.
- **Cari travel (daftar driver):** Firebase Analytics `passenger_active_drivers_source` (`source`, `result_count`, `reason`, `fs_cap=1` jika plafon Firestore tercapai). Fallback Firestore: **limit 400**, `orderBy lastUpdated desc` (indeks `driver_status`: `status` + `lastUpdated` di `firestore.indexes.json` — deploy indeks sebelum mengandalkan query di produksi). Breadcrumb: `firestore_fallback`, `firestore_cap_hit`.
- **Penumpang — form Cari jadwal (terjadwal):** `showDatePicker` memakai `todayDateOnlyWib` … `lastScheduleDateInclusiveWib` (selaras jendela 7 hari WIB driver). `getScheduledDriversForMap` memfilter jam lewat dengan **hari ini WIB**. Lihat skenario **1.5**.
- **Observabilitas (Crashlytics / Analytics):** breadcrumb `[DriverHybrid] schedules.full_scan op=map_for_date|recommend_for_date docs=… ms=… results=…` hanya jika scan koleksi `driver_schedules` **lambat** (≥ ~2,5 s) atau **banyak dokumen** (≥ ~80); custom keys `last_schedules_scan_ms`, `last_schedules_scan_docs`, `last_schedules_scan_op`. Di **debug**, setiap scan juga tercetak ke konsol. Firebase Analytics: **`hybrid_driver_location_rate_limited`** bila `POST /api/driver/location` mendapat **429** (selaras rate limit server).
- **Jadwal driver (subkoleksi):** slot di `driver_schedules/{uid}/schedule_items/{id}`. Indeks query tanggal memakai **`fieldOverrides`** (`schedule_items` / `date` / `COLLECTION_GROUP`) di `firestore.indexes.json` — bukan satu-field di blok `indexes` (deploy Firebase menolak dengan *index is not necessary*). **Deploy** rules + indexes + Functions (`onDriverScheduleItemWritten`).
- Satu lembar ini = satu kombinasi **Build app + API URL**; ganti build → duplikat blok **Sesi uji** atau buat baris baru di dokumen salinan.

## Tautan terkait

- [`KESIAPAN_SKALA_JUTAAN_PENGGUNA.md`](KESIAPAN_SKALA_JUTAAN_PENGGUNA.md) — fokus operasional mingguan + checklist sebelum klaim skala jutaan
- [`../traka-api/docs/RAILWAY_DEPLOY_CEPAT.md`](../traka-api/docs/RAILWAY_DEPLOY_CEPAT.md) — redeploy Railway + env (termasuk rate limit lokasi driver)
- [`README.md`](../README.md) — mode hybrid & skrip run/build
- [`TAHAPAN_MIGRASI_INFRA_4_FASE.md`](TAHAPAN_MIGRASI_INFRA_4_FASE.md) — **Tahap 1–4** (observabilitas → realtime)
- [`../traka-api/docs/TAHAPAN_1_OBSERVABILITAS.md`](../traka-api/docs/TAHAPAN_1_OBSERVABILITAS.md) — **Tahap 1**: `/health`, UptimeRobot, Sentry, QA baseline
- [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md) — alur umum
- [`ROADMAP_INFRASTRUKTUR_SKALA.md`](ROADMAP_INFRASTRUKTUR_SKALA.md) — WS / tahap skala
