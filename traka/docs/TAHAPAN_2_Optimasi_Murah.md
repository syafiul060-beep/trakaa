# Tahap 2 — Optimasi murah (Firestore / CPU, tanpa WebSocket)

Dokumen ini melengkapi [`TAHAPAN_MIGRASI_INFRA_4_FASE.md`](TAHAPAN_MIGRASI_INFRA_4_FASE.md) bagian **Tahap 2**: apa yang sudah ada di kode, apa yang bisa dioptimasi bertahap, dan **apa yang Anda ukur manual** di Firebase.

**Prinsip:** perubahan **kecil per PR**; uji di perangkat nyata sebelum menaikkan angka throttle atau menurunkan frekuensi update.

---

## Tujuan

- Kurangi **Firestore reads** dan beban **CPU/UI** (peta, marker, listener).
- **Tidak** menambah infra (WebSocket = Tahap 4).
- **Gate:** metrik tidak memburuk (atau lebih baik) **dan** UX peta/order tidak terasa “patah”.

---

## Cara menyelesaikan Tahap 2 (urutan praktis)

Ikuti **berurutan**. Jangan loncat ke “Tahap 2 selesai” hanya karena baseline sudah dicatat — gate membutuhkan **minimal satu** optimasi ter-deploy **dan** perbandingan + QA.

### Langkah 1 — Baseline (sebelum ubah kode)

1. Firebase Console → **Firestore** → **Usage**.
2. Pilih rentang **24 jam** atau **7 hari** (gunakan **jenis rentang yang sama** nanti saat banding).
3. Catat di catatan: **tanggal**, **reads**, **writes**, **deletes** (screenshot atau tabel).

*(Anda sudah punya contoh baseline 24 jam — simpan sebagai “sebelum #1”.)*

### Langkah 2 — Pilih **satu** optimasi (jangan banyak sekaligus)

Contoh aman untuk percobaan pertama:

- Naikkan `passengerMapInterpolationIntervalMs` sedikit (mis. **96** → **100**) di `lib/config/app_constants.dart` (hemat sedikit `setState`/frame di peta penumpang), **atau**
- Tinjau satu layar yang punya **listener** Firestore lebar → sempitkan query (PR terpisah, butuh baca kode).

### Langkah 3 — Uji lokal

1. `flutter run` di perangkat nyata (bukan hanya emulator jika bisa).
2. Buka **peta penumpang** dengan banyak marker; geser/zoom — pastikan tidak terasa “patah” berlebihan.
3. `flutter test` jika ada test yang relevan.

### Langkah 4 — Commit, build rilis, deploy

1. Commit dengan pesan jelas (mis. `perf: passenger map interpolation 80→100ms`).
2. Build **release** / upload Play Store / TestFlight sesuai alur Anda ([`BUILD_PLAY_STORE.md`](BUILD_PLAY_STORE.md)).
3. Tunggu pengguna (atau diri sendiri) memakai build baru.

### Langkah 5 — Metrik “sesudah”

1. **Minimal 24 jam** setelah build baru dipakai (lebih baik **3–7 hari** traffic normal).
2. Firebase → Firestore → **Usage** → **rentang sama** seperti baseline (mis. tetap 24 jam).
3. Bandingkan reads/writes. Naik sedikit bisa wajar jika **lebih banyak order**; yang dicurigai: reads **melonjak** tanpa kenaikan penggunaan app.

### Langkah 6 — QA singkat

1. Jalankan minimal: beranda peta → cari driver → satu alur order atau proximity ([`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md) blok A + peta).
2. Catat **tanggal** + **versi build** + lulus/gagal.

### Langkah 7 — Tutup Tahap 2

Centang [`Gate Tahap 2 selesai`](#gate-tahap-2-selesai) di bawah. Baru lanjut **Tahap 3** ([`TAHAPAN_MIGRASI_INFRA_4_FASE.md`](TAHAPAN_MIGRASI_INFRA_4_FASE.md)).

**Jika Anda belum mengubah kode sama sekali:** Tahap 2 belum selesai — Anda baru di **Langkah 1**. Itu wajar; lanjutkan dari Langkah 2 ketika siap.

---

## Yang sudah ada di repo (titik pegangan)

| Area | File / konstanta | Keterangan |
|------|-------------------|------------|
| Interpolasi marker multi-driver (penumpang) | `lib/config/app_constants.dart` → `passengerMapInterpolationIntervalMs` (default **100** ms usai Tahap 2 ini) | Trade-off UX vs CPU; naikkan bertahap hanya setelah uji (mis. hingga 120 ms). |
| Bearing ikon mobil | `passengerMapBearingSmoothAlpha` | Smoothing heading, bukan throttle waktu. |
| Maks driver di peta pencarian | `maxDriversOnPassengerSearchMap` (**50**) | Batas atas marker setelah filter rute. |
| Timer interpolasi peta | `lib/screens/penumpang_screen.dart` | `Timer.periodic` memakai `passengerMapInterpolationIntervalMs`. |
| Driver: reverse geocode / directions | `lib/screens/driver_screen.dart` | Sudah ada **debounce/throttle** untuk nama jalan & arah (kurangi API + setState). |
| Muat driver aktif (travel) | `lib/services/active_drivers_service.dart` | Query **get()** ke `driver_status` + batch `users` / `vehicle_data` — tinjau ulang bila menambah field atau memperluas query. |
| Hybrid API | `lib/config/traka_api_config.dart` | Saat `TRAKA_USE_HYBRID=true`, sebagian status bisa lewat Redis/API (Tahap 3), mengurangi tekanan Firestore untuk path yang sudah dimigrasi. |

Rujukan UX/performa UI: [`PERBAIKAN_UI_UX_PERFORMA_2025-03.md`](PERBAIKAN_UI_UX_PERFORMA_2025-03.md) (trace Performance **tidak** mengubah frekuensi update peta).

---

## Optimasi kode (urutan kerja disarankan)

Lakukan **satu** perubahan dominan per rilis kecil, lalu ukur.

1. **Peta penumpang:** sesuaikan `passengerMapInterpolationIntervalMs` (mis. 96 → 100, lalu uji) **hanya** jika sudah baseline metrik / frame — build uji internal dulu.
2. **Marker / viewport:** pastikan filter jarak + `maxDriversOnPassengerSearchMap` tetap relevan; jangan naikkan batas tanpa alasan (lebih banyak marker = lebih berat).
3. **Firestore:** hindari **listener** pada koleksi besar tanpa `where` + batas; untuk daftar order aktif, scope ke `userId` / `orderId` yang relevan (tinjau per layar).
4. **Driver → API:** dokumentasi tier update lokasi / proximity: [`NOTIFIKASI_JARAK_PENUMPANG_DRIVER.md`](NOTIFIKASI_JARAK_PENUMPANG_DRIVER.md) (jika ada); selaraskan dengan `OrderService` / policy jarak agar tidak menulis Firestore lebih sering dari kebutuhan.

---

## Yang Anda lakukan secara manual

### 1) Baseline metrik (sebelum ubah besar)

1. [Firebase Console](https://console.firebase.google.com) → project Traka → **Firestore** → tab **Usage** (atau **Billing / Usage** tergantung UI).
2. Catat **reads/hari** (dan **writes** jika relevan) selama **3–7 hari** normal — ini baseline **sebelum** optimasi besar.
3. Opsional: **Functions** → usage invocations jika Anda curiga cold start / pemanggilan berlebihan.

### 2) Setelah deploy build yang berisi optimasi

1. Bandingkan **reads** per hari (minggu yang sama vs minggu sebelumnya — perhatikan lonjakan traffic organik).
2. Di **Performance** (jika trace aktif): bandingkan `passenger_map_ready` / startup tidak memburuk.
3. Di perangkat: **scroll peta**, **cari driver**, **order aktif** — peta harus tetap halus (bukan “sekat” berlebihan).

### 3) QA regresi (minimal Tahap 2)

- Ulang skenario **proximity**, **chat**, **order aktif** dari [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md) (minimal blok A + satu skenario peta).
- Atau gunakan catatan singkat seperti [`QA_BASELINE_TAHAP1_TEMPLATE.md`](QA_BASELINE_TAHAP1_TEMPLATE.md) dengan fokus “setelah optimasi Tahap 2”.

---

## Gate Tahap 2 selesai

- [OK] Ada **baseline** metrik Firestore (tangkapan angka atau catatan) sebelum perubahan signifikan.
- [OK] Setelah perubahan: **reads flat atau turun** (atai naik proporsional traffic) **dan** tidak ada keluhan UX peta/order.
- [OK] Satu putaran **QA** relevan tercatat.

**Lanjut:** [`TAHAPAN_MIGRASI_INFRA_4_FASE.md`](TAHAPAN_MIGRASI_INFRA_4_FASE.md) — **Tahap 3** (scale API + Redis + hybrid).

---

## Checklist cepat

| Item | Manual / kode |
|------|------------------|
| Catat Firestore reads (Console) | Manual |
| Sesuaikan `passengerMapInterpolationIntervalMs` / `maxDriversOnPassengerSearchMap` | Kode + uji |
| Tinjau query/listener per fitur | Kode (PR terpisah) |
| QA peta + order | Manual |

*Tinjau dokumen ini setelah setiap rilis yang menyentuh peta atau Firestore.*
