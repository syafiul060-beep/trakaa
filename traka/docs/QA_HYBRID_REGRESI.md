# QA regresi mode hybrid

Dokumen ini untuk uji cepat sebelum rilis ketika app dibuild dengan **`TRAKA_USE_HYBRID=true`** + **`TRAKA_API_BASE_URL`** (lihat `scripts/build_hybrid.ps1`). Tanpa itu, banyak fitur API tidak jalan — itu bukan bug, melainkan mode “Firestore-only”.

---

## Sesi uji (isi sebelum mulai)

| Field | Nilai |
|-------|--------|
| **Tanggal** | _YYYY-MM-DD_ |
| **Tester** | _nama_ |
| **Lingkungan** | ☐ Staging &nbsp; ☐ Production &nbsp; ☐ Lain: _______ |
| **`TRAKA_API_BASE_URL`** (yang dipakai build) | _https://…_ |
| **Build app** (version + build / CI #) | _mis. 1.4.0 (210) atau #456_ |
| **Define opsional** (centang jika dipakai di build ini) | ☐ `TRAKA_CREATE_ORDER_VIA_API` ☐ `TRAKA_API_CERT_SHA256` ☐ Map WS (`TRAKA_ENABLE_MAP_WS` + URL) |
| **Firebase project** (jika relevan) | _default / alias_ |
| **Commit / tag API** (server yang dilayani oleh URL di atas) | _mis. `main` @ abc1234_ |
| **Layanan backend** (cek cepat) | ☐ Postgres order aktif ☐ Redis driver ☐ WebSocket map (jika dipakai) |

_Isi **Pass/Fail** di tabel dengan `PASS` / `FAIL` / `N/A`. **Catatan** untuk nomor issue, screenshot, atau perangkat._

**Arsip rilis:** Simpan salinan baris **Sesi uji** + **Ringkasan** (copy ke issue release / Notion) agar setiap build bisa dilacak tanpa tebak-tebak URL atau commit.

---

## Smoke API pasca-deploy (~5 menit)

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

---

## 1. Order + API (penumpang)

| # | Skenario | Langkah / cek | Diharapkan | Pass/Fail | Catatan |
|---|----------|---------------|------------|-----------|---------|
| 1.1 | Buat order travel | Penumpang: cari driver → buat pesanan | Order muncul di Data Order + chat; driver melihat pesanan. | | |
| 1.2 | Buat order (via API) | Hanya jika define **CREATE_ORDER_VIA_API**: buat pesanan baru | Sukses; tidak ada duplikat / order hantu di UI. | | |
| 1.3 | Fallback API | Dev: API tidak terjangkau lalu buat order | Tetap bisa lewat Firestore atau pesan error jelas (sesuai kode). | | |
| 1.4 | Kirim barang + bayar hybrid | Alur ongkos pengirim/penerima sebelum scan | Gate scan / sheet pembayaran sesuai `OrderModel.hybridPay*`. | | |

---

## 2. Driver status + matching (Redis / API)

| # | Skenario | Langkah / cek | Diharapkan | Pass/Fail | Catatan |
|---|----------|---------------|------------|-----------|---------|
| 2.1 | Siap kerja | Driver: pilih rute → mulai bekerja | Penumpang di filter/radius melihat driver (path hybrid). | | |
| 2.2 | Update lokasi | Driver bergerak ±2–5 menit | Posisi di peta penumpang terbarui (polling atau WS). | | |
| 2.3 | API error | Hybrid on; respons API gagal (staging) | Tidak crash; degradasi/fallback masuk akal. | | |

---

## 3. Jadwal driver (Firestore + recovery hybrid)

| # | Skenario | Langkah / cek | Diharapkan | Pass/Fail | Catatan |
|---|----------|---------------|------------|-----------|---------|
| 3.1 | Tambah / edit / hapus | Simpan jadwal | Sheet tutup cepat; snackbar; daftar konsisten; gagal upload → merah + rollback daftar. | | |
| 3.2 | Background recovery | ±5 s background → buka tab Jadwal atau Chat | Data tidak “nyangkut” (HybridForegroundRecovery). | | |
| 3.3 | Sinkron manual | Profil driver → sinkronkan data (jika tersedia) | Jadwal/chat/order terasa segar. | | |

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
- Satu lembar ini = satu kombinasi **Build app + API URL**; ganti build → duplikat blok **Sesi uji** atau buat baris baru di dokumen salinan.

## Tautan terkait

- [`README.md`](../README.md) — mode hybrid & skrip run/build
- [`TAHAPAN_MIGRASI_INFRA_4_FASE.md`](TAHAPAN_MIGRASI_INFRA_4_FASE.md) — **Tahap 1–4** (observabilitas → realtime)
- [`../traka-api/docs/TAHAPAN_1_OBSERVABILITAS.md`](../traka-api/docs/TAHAPAN_1_OBSERVABILITAS.md) — **Tahap 1**: `/health`, UptimeRobot, Sentry, QA baseline
- [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md) — alur umum
- [`ROADMAP_INFRASTRUKTUR_SKALA.md`](ROADMAP_INFRASTRUKTUR_SKALA.md) — WS / tahap skala
