# Tahap 3 — Scale API + Redis + hybrid (driver_status lewat API)

Dokumen ini melengkapi [`TAHAPAN_MIGRASI_INFRA_4_FASE.md`](TAHAPAN_MIGRASI_INFRA_4_FASE.md) bagian **Tahap 3**.

**Prasyarat:** API produksi sudah stabil ([Tahap 1](../traka-api/docs/TAHAPAN_1_OBSERVABILITAS.md)); UX/metrik app tidak memburuk ([Tahap 2](TAHAPAN_2_Optimasi_Murah.md)). **Redis** untuk API Anda sudah dipakai jika `GET /health` menunjukkan `checks.redis: true` (Railway + `REDIS_URL`).

---

## Tujuan

- Beberapa **instance** API bisa jalan paralel; **Redis** tetap pusat **geo / matching / rate limit** (shared antar instance).
- App Flutter: opsi **hybrid** — sebagian **`driver_status`** dan path terkait lewat **REST API** (Redis di belakang), bukan hanya Firestore.
- Rollout **bertahap** (internal → beta → penuh) dengan **rollback** jelas.

---

## Langkah berikutnya — mulai sekarang (urutan)

Ikuti **berurutan**. Detail teknis ada di bagian **1)–3)** di bawah.

| # | Apa | Tujuan |
|---|-----|--------|
| 1 | Buka `GET …/health` produksi | Pastikan `ok: true`, `checks.redis: true` sebelum build hybrid. |
| 2 | Dari folder `traka/`, jalankan `.\scripts\build_hybrid.ps1` dengan `-ApiUrl` API Anda | Hasilkan APK/AAB dengan `TRAKA_USE_HYBRID=true` + URL API. |
| 3 | Pasang build di **HP Anda** (sideload APK atau track internal) | Uji manual sebelum pengguna lain. |
| 4 | Uji alur: driver online → penumpang cari driver → travel/order singkat | Memastikan hybrid tidak merusak matching / status. |
| 5 | Unggah **AAB** ke Play Console → **Internal testing** (bukan production dulu) | Rollout bertahap. |
| 6 | Pantau **Sentry** (API) + **UptimeRobot** (`/health`) beberapa hari | Incident cepat terlihat. |
| 7 | (Opsional) Build berikutnya tambah **`TRAKA_API_CERT_SHA256`** setelah uji internal | Pinning — lihat [`SETUP_CERTIFICATE_PINNING.md`](SETUP_CERTIFICATE_PINNING.md). |
| 8 | **Production** Play hanya setelah internal/beta stabil; simpan **AAB lama tanpa hybrid** untuk rollback | — |
| 9 | **Jangan** mulai **Tahap 4** (WebSocket massal) sebelum hybrid + Redis terasa stabil | Urutan roadmap. |

**Perintah build (contoh Windows, dari `D:\Traka\traka`):**

```powershell
cd D:\Traka\traka
.\scripts\build_hybrid.ps1 -ApiUrl "https://trakaa-production.up.railway.app" -Target apk
```

Untuk rilis Play: ganti `-Target appbundle`. Lihat juga [`BUILD_PLAY_STORE.md`](BUILD_PLAY_STORE.md).

### Uji lewat USB ke HP dulu (sebelum unggah Play)

Ini **disarankan**: sama-sama mode hybrid, lebih cepat iterasi daripada internal track.

1. **Di HP Android:** **Pengaturan** → **Tentang ponsel** → ketuk **Nomor build** 7× → kembali → **Opsi pengembang** → aktifkan **Debugging USB**.
2. **Sambungkan USB** ke PC → di HP, izinkan **debugging USB** / **percayai komputer** jika muncul dialog.
3. Di PC (folder `traka/`):

   ```cmd
   cd D:\Traka\traka
   .\scripts\run_hybrid.bat
   ```

   (Setara: `run_hybrid.ps1` — lihat [`CARA_JALANKAN_DARI_CMD.md`](CARA_JALANKAN_DARI_CMD.md).) Flutter akan memasang **debug build** ke HP dengan `TRAKA_USE_HYBRID=true` + URL API default Railway.

4. Jika beberapa device: `flutter devices` lalu `.\scripts\run_hybrid.ps1 -Device <device_id>`.

**Alternatif — pasang APK release lewat USB** (tanpa `flutter run`):

1. Build: `.\scripts\build_hybrid.ps1 -ApiUrl "https://trakaa-production.up.railway.app" -Target apk`
2. Pasang: `adb install -r build\app\outputs\flutter-apk\app-release.apk`  
   (`adb` dari Android SDK / platform-tools; HP tetap USB debugging aktif.)

---

## Yang relevan di repo

| Komponen | Lokasi |
|----------|--------|
| Konfigurasi klien | `lib/config/traka_api_config.dart` — `TRAKA_API_BASE_URL`, `TRAKA_USE_HYBRID`, `TRAKA_API_CERT_SHA256` |
| Hybrid driver status | `lib/services/driver_status_service.dart` |
| Daftar driver aktif (travel) | `lib/services/active_drivers_service.dart` — cabang `TrakaApiConfig.isApiEnabled` |
| HTTP ke API + pinning | `lib/services/traka_api_service.dart` |
| Build hybrid (PowerShell) | `scripts/build_hybrid.ps1` |
| Certificate pinning | [`SETUP_CERTIFICATE_PINNING.md`](SETUP_CERTIFICATE_PINNING.md) |
| Redis produksi (API) | [`../traka-api/docs/SETUP_REDIS_PRODUCTION.md`](../traka-api/docs/SETUP_REDIS_PRODUCTION.md) |
| Geo matching API | [`../traka-api/docs/REDIS_GEO_MATCHING.md`](../traka-api/docs/REDIS_GEO_MATCHING.md) |

`isApiEnabled` = **true** hanya jika **`TRAKA_API_BASE_URL` tidak kosong** dan **`TRAKA_USE_HYBRID=true`** di **build** (`--dart-define`).

---

## 1) Redis + API (server) — cek ulang

1. **Railway** (atau host Anda): `REDIS_URL` valid, TLS jika provider mewajibkan (`rediss://` — lihat dokumen Redis).
2. **`GET /health`** → `ok: true`, `checks.redis: true`.
3. **Jangan** expose Redis ke publik; hanya dari API/worker.
4. **Scale horizontal:** di Railway, naikkan **replicas** / jumlah instance jika tersedia; semua instance harus **env sama** (`REDIS_URL`, `DATABASE_URL`, Firebase, dll.).
5. **`APP_VERSION`** tetap di-set per deploy untuk jejak versi.

---

## 2) Build app dengan hybrid

### Menggunakan skrip (disarankan)

Dari root proyek Flutter (`traka/`):

```powershell
.\scripts\build_hybrid.ps1 -ApiUrl "https://trakaa-production.up.railway.app" -Target appbundle
```

Ganti URL dengan domain API Anda (tanpa trailing slash). Skrip men-set `TRAKA_USE_HYBRID=true` + `TRAKA_API_BASE_URL`.

### Manual

```text
flutter build appbundle ^
  --dart-define=TRAKA_API_BASE_URL=https://trakaa-production.up.railway.app ^
  --dart-define=TRAKA_USE_HYBRID=true
```

Tambahkan `MAPS_API_KEY` jika diperlukan (lihat `build_hybrid.ps1`).

### Certificate pinning (opsional, disarankan produksi)

```text
--dart-define=TRAKA_API_CERT_SHA256=AA:BB:CC:...
```

Ambil fingerprint dengan langkah di [`SETUP_CERTIFICATE_PINNING.md`](SETUP_CERTIFICATE_PINNING.md). **Salah fingerprint = API tidak terhubung** — uji di internal dulu.

---

## 3) Rollout bertahap

| Urutan | Tindakan |
|--------|----------|
| 1 | Build hybrid → pasang di **perangkat internal** / **internal testing** (Play). |
| 2 | Uji: driver **online/offline**, **cari driver** penumpang, **order** travel yang menyentuh `driver_status` / matching. |
| 3 | **Beta terbuka** atau kelompok kecil. |
| 4 | Penuh — pantau Sentry (API + app), `/health`, dan Firestore Usage (beban Firestore pada path yang dipindah seharusnya berkurang untuk fitur yang sudah hybrid). |

**Rollback app:** rilis build dengan `TRAKA_USE_HYBRID=false` atau tanpa `TRAKA_API_BASE_URL` (default kode) — kembali mengandalkan Firestore untuk path yang belum di-migrate di server (pastikan perilaku ini masih didukung sampai migrasi penuh).

---

## 4) Yang tidak perlu untuk Tahap 3

- **App Engine** di GCP **bukan** syarat jika API sudah di **Railway** — hindari dua host API produksi tanpa alasan.
- **Tahap 4** (WebSocket massal) — **belakangan**, setelah hybrid + Redis stabil.

---

## Gate Tahap 3 selesai

- [ ] `/health` produksi: `ok: true`, `redis: true`.
- [ ] Satu build **hybrid** teruji (driver + penumpang, alur utama).
- [ ] Rollout ada **rencana** (internal → beta → penuh) dan **rollback** jelas.
- [ ] (Opsional) Pinning aktif atau disengaja tidak dipakai dengan alasan dokumentasi.

**Lanjut:** [`TAHAPAN_MIGRASI_INFRA_4_FASE.md`](TAHAPAN_MIGRASI_INFRA_4_FASE.md) — **Tahap 4** (Redis publish → worker → WebSocket).

---

## Checklist cepat

| Item | Di mana |
|------|---------|
| `REDIS_URL` + health | Railway Variables + `GET /health` |
| Scale instance | Railway / panel host |
| `build_hybrid.ps1` / `--dart-define` | Lokal / CI |
| Pinning | `SETUP_CERTIFICATE_PINNING.md` |

*Tinjau ulang setelah mengubah domain API atau provider Redis.*
