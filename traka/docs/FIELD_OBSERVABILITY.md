# Observabilitas lapangan (Tahap 5)

Ringkasan tempat init global & Performance: [`ROLE_GLOBAL_SERVICE_INVENTORY.md`](ROLE_GLOBAL_SERVICE_INVENTORY.md) §9.

## Crashlytics — breadcrumb & custom keys

Saat driver atau penumpang memakai bottom navigation utama, app menulis:

- **Log (breadcrumb)** ke Crashlytics, mis. `[Field] driver tab=home_map navigating=true order=<id>`
- **Custom keys** pada laporan error berikutnya (crash / non-fatal):
  - Driver: `driver_tab`, `driver_route_nav`, `driver_order_nav_id`
  - Penumpang: `passenger_tab`, `passenger_tracking_drivers`

`driver_route_nav` bernilai true bila **rute kerja aktif** atau **navigasi ke order** (jemput/antar) sedang berjalan. `navigating` di log mengikuti definisi yang sama.

Implementasi: `lib/services/field_observability_service.dart`, dipanggil dari `driver_screen.dart` dan `penumpang_screen.dart` (sinkronisasi tab + resume + perubahan state navigasi).

## Matriks QA perangkat (disarankan)

| Kelas | Contoh perangkat | Fokus |
|--------|-------------------|--------|
| Entry / murah | RAM 2–3 GB, Android 11–13 | Cold start, peta driver + penumpang, scroll jadwal/order, navigasi + voice |
| Menengah | RAM 4 GB, refresh rate 60 Hz | Hybrid lokasi, chat + notifikasi tab, restore rute |
| Flagship | RAM 8 GB+, 120 Hz | Kamera ikut bearing, premium nav, multitasking (home → kembali) |

Untuk tiap kelas, minimal satu jalur: **driver** mulai kerja → peta → chat → order; **penumpang** cari driver → lacak di peta → order.

## Android Vitals & ANR di Play Console

1. **Play Console** → aplikasi → **Kualitas** → **Android vitals** (atau **Kestabilan** tergantung tampilan konsol).
2. Pantau **tingkat ANR**, **tingkat crash**, dan **kelumpuhan UI** (freeze / frame jank agregat).
3. Bandingkan per **versi app**, **model perangkat**, dan **versi Android** untuk melihat apakah regresi terkait rilis tertentu atau kelas perangkat.
4. Untuk ANR: buka detail → **stack trace** / **“Traces”** — cocokkan dengan waktu breadcrumb `[Field]` di Crashlytics (user yang sama / waktu mendekati) bila perlu.

Catatan: **Firebase Crashlytics** tidak menggantikan metrik ANR resmi Play; keduanya saling melengkapi. ProGuard/R8 **mapping** sudah diaktifkan untuk build release (lihat `docs/BUILD_PLAY_STORE.md`) agar stack trace di Firebase terbaca.

## Firebase Performance

Di `main.dart`, koleksi Performance Monitoring diaktifkan (`setPerformanceCollectionEnabled(true)`) untuk trace performa jaringan/SDK; gunakan bersamaan dengan vitals di atas.

## Review mingguan — korelasi metrik (satu ritual, bukan kode baru)

Tujuan: **melihat pola** (versi app × waktu × backend × Firestore) sebelum menyalahkan perangkat atau menambah logika defensif tanpa sinyal.

### Sumber yang diselaraskan (jendela waktu sama, mis. 7 hari terakhir)

| Sinyal | Di mana | Yang dicatat untuk korelasi |
|--------|---------|-----------------------------|
| **Versi app & stabilitas klien** | Play Console → Android vitals | Versi yang naik staging/production, % ANR / crash / freeze; model/ABI bermasalah |
| **Crash & konteks tab/nav** | Firebase Crashlytics | Issue baru, custom keys driver/passenger, breadcrumb `[Field]` / `[DriverHybrid]` (lihat [`QA_HYBRID_REGRESI.md`](QA_HYBRID_REGRESI.md)) |
| **Firebase backend** | Console → Firestore **Usage** | Read/write/delete, bandingkan minggu ini vs minggu lalu; lonjakan tanpa penjelasan |
| **Functions** | Console → Functions (log/error, cold start) | Deploy tanggal/jam; error rate setelah deploy |
| **API produksi** | Railway (deploy log) + Sentry (API) | Rilis `APP_VERSION` / redeploy; spike issue atau latency di Sentry |
| **Uptime kasar** | UptimeRobot (jika dipakai) | Inciden down bertepatan dengan deploy atau lonjakan user |

Dokumen terkait: [`../traka-api/docs/TAHAPAN_1_OBSERVABILITAS.md`](../traka-api/docs/TAHAPAN_1_OBSERVABILITAS.md), [`TAHAPAN_2_Optimasi_Murah.md`](TAHAPAN_2_Optimasi_Murah.md) (baseline Firestore).

### Template catatan mingguan (salin ke Notion / Sheet)

Isi sekali per minggu; **waktu referensi**: rentang tanggal + zona waktu operasi.

| Kolom | Isi |
|-------|-----|
| Periode | Mis. 22–28 Mar 2026 |
| Versi app di Play | Kode versi / % rollout per jalur |
| Deploy backend | API (Railway) + Functions (Firebase): tanggal & ringkas perubahan |
| Vitals / Crashlytics | Naik/turun vs minggu lalu; 1–2 issue teratas + versi |
| Firestore usage | Read/write: naik % berapa; ada event deploy/client baru? |
| Sentry API | Issue baru / spike; endpoint atau route terkait |
| Hipotesis | Satu kalimat: “lonjakan read setelah rilis X” atau “noise OEM” |
| Tindakan | Mis. lanjut rollout / tahan rilis / pantau saja / tiket |

### Aturan praktis

1. **Samakan rentang tanggal** di semua konsol sebelum menyimpulkan regresi.
2. **Catat deploy** (Functions, API, app) di baris yang sama dengan lonjakan metrik — sering menjelaskan lonjakan Firestore atau error.
3. Jika **Firestore naik** tanpa deploy server: curigai **versi app baru** atau **perilaku klien** (listener/query); cocokkan % adop versi di Play.
4. Jika **Sentry API** dan **Crashlytics** keduanya naik ke arah yang sama: prioritaskan **alur hybrid + lokasi** (lihat [`QA_HYBRID_REGRESI.md`](QA_HYBRID_REGRESI.md)); jika hanya salah satu, jangan menyamakan penyebab tanpa bukti waktu.
