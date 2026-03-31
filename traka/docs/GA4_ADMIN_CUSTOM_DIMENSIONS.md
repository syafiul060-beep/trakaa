# GA4: Custom dimension untuk admin (lacak & GPS)

Tujuan: parameter event dari app Traka bisa dipakai sebagai **dimensi** di **Explorations** dan laporan GA4, sehingga admin bisa memfilter dan mengevaluasi tanpa query BigQuery.

> **Yang dilakukan di kode:** sudah — app mengirim parameter dengan nama tetap di bawah.  
> **Yang dilakukan manual (sekali per property GA4):** daftar **Custom dimension** di konsol Google Analytics sesuai tabel ini. Tidak ada API wajib dari Firebase untuk ini.

## Prasyarat

- Aplikasi Traka terhubung ke properti **Google Analytics 4** (biasanya otomatis lewat Firebase).
- Akun Anda punya peran **Editor** atau **Administrator** di GA4.

## Langkah di Google Analytics 4

1. Buka [Google Analytics](https://analytics.google.com/) → pilih **properti** yang dipakai Traka.
2. **Admin** (ikon gigi, kiri bawah).
3. Di kolom **Properti**: **Tampilan data** → **Definisi kustom** → **Buat dimensi kustom** (*Custom dimension*).
4. Isi:
   - **Nama dimensi**: label yang muncul di laporan (bebas, mis. `Alasan berbagi lokasi berhenti`).
   - **Cakupan**: **Peristiwa** (*Event*).
   - **Parameter peristiwa**: **harus sama persis** dengan nama di tabel di bawah (huruf kecil/besar ikut kode).

5. Simpan. **Historis:** nilai baru mulai terisi setelah dimensi aktif; data lama sebelum pembuatan dimensi biasanya **tidak** diisi balik untuk dimensi baru (tergantung GA4; umumnya mulai dari data baru).

6. Uji: **Explore** → Blank → pilih dimensi kustom + **Nama peristiwa** sebagai filter.

## Batasan

- Properti GA4 standar punya batas jumlah **dimensi kustom per peristiwa** (cek dokumen Google terbaru; sering sekitar 50 total event-scoped). Prioritaskan baris yang penting untuk evaluasi admin.
- Satu **nama parameter** (`reason`, `flow`, dll.) bisa muncul di **beberapa** nama peristiwa berbeda — di Explorations selalu **filter “Nama peristiwa”** dulu agar interpretasi tidak tercampur.

## Daftar yang disarankan (Traka — lacak / GPS)

| Nama dimensi (tampilan, contoh) | Parameter peristiwa (wajib persis) | Peristiwa utama (filter di GA4) | Nilai contoh / catatan |
|--------------------------------|--------------------------------------|-----------------------------------|-------------------------|
| Lacak — alur layar | `flow` | `lacak_open`, `lacak_stale_banner_shown` | `driver`, `kirim_barang` |
| Lacak — penyebab banner | `reason` | `lacak_stale_banner_shown` | `connection`, `stale` |
| Lacak — audience bantuan | `audience` | `lacak_help_open` | `lacakDriverMap`, `lacakBarangMap`, `profilePenumpang`, `profileDriver` |
| Driver — alasan tracking berhenti | `reason` | `driver_tracking_stopped` | `end_work`, `became_inactive` |
| Driver — tracking berhenti di latar belakang | `in_background` | `driver_tracking_stopped` | `true`, `false` (string dari app) |
| Penumpang — alasan share lokasi berhenti | `reason` | `passenger_share_stopped` | `no_eligible_orders`, `logout` |
| Kirim barang — status dari | `from` | `lacak_phase_switch_barang` | Nilai status order (Firestore) |
| Kirim barang — status ke | `to` | `lacak_phase_switch_barang` | Idem |
| Driver nav — premium UI aktif | `enabled` | `driver_nav_premium_ui` | `true` / `false` (string) |
| Driver nav — sumber premium | `source` | `driver_nav_premium_ui` | `map_tap` \| `prepay_success` \| `exempt` \| `persist_restore` |
| Driver nav — pemicu reroute | `trigger` | `driver_nav_reroute` | `auto_deviation` \| `auto_missed_turn` \| `auto_long_leg` \| `manual_refresh` \| `online_flush` \| `after_pickup` |
| Driver nav — cakupan rute reroute | `scope` | `driver_nav_reroute` | `main` \| `to_passenger` \| `to_destination` |
| Driver nav — mode kualitas premium aktif | `premium_quality` | `driver_nav_reroute`, `driver_nav_route_deviation_sample` | `true` / `false` (sesi kerja/nav order + premium UI) |
| Driver nav — sukses polyline reroute | `success` | `driver_nav_reroute` | `true` / `false` |
| Driver nav — bucket simpangan (meter) | `deviation_bucket` | `driver_nav_reroute`, `driver_nav_route_deviation_sample` | `0_25` \| `25_50` \| `50_80` \| `80_120` \| `120_plus` |
| Driver nav — konteks peta | `nav_context` | `driver_nav_route_deviation_sample` | `main_work` \| `to_passenger` \| `to_destination` \| (`inactive` cadangan) |

**Setelah didaftarkan di konsol:** label **Nama dimensi** boleh berbeda (mis. `driver_nav_reroute2` untuk parameter `trigger`); yang tidak boleh salah adalah **Parameter peristiwa** — harus sama dengan tabel dan dengan yang dikirim app (`lib/services/app_analytics_service.dart`).

### Parameter yang sama di banyak peristiwa

- **`reason`**: dipakai di `lacak_stale_banner_shown`, `driver_tracking_stopped`, `passenger_share_stopped`. **Wajib filter “Nama peristiwa”** saat menganalisis.

- **`flow`**: dipakai di `lacak_open`, `lacak_stale_banner_shown`.

- **`premium_quality`**: dipakai di `driver_nav_reroute` dan `driver_nav_route_deviation_sample` — **wajib filter “Nama peristiwa”** bila menggabungkan dengan event lain yang kelak memakai nama parameter sama.

- **`deviation_bucket`**: dipakai di `driver_nav_reroute` (opsional, biasanya rute `main` + pemicu `auto_deviation`) dan `driver_nav_route_deviation_sample`.

## BigQuery

Jika export BigQuery aktif, parameter tetap ada di tabel peristiwa **tanpa** mendaftarkan custom dimension. Custom dimension ini khusus untuk **antarmuka GA4** bagi admin.

## Rujukan kode

- `lib/services/app_analytics_service.dart` — nama peristiwa dan parameter.
- `docs/GPS_LIFECYCLE_TRAKA.md` — arti bisnis siklus GPS.

## Parameter tidak muncul di dropdown GA4?

Daftar **Pilih parameter peristiwa** di form dimensi kustom hanya berisi parameter yang **sudah pernah diterima** properti dari peristiwa nyata. Untuk `driver_nav_reroute` / `driver_nav_route_deviation_sample`, nama seperti `trigger`, `premium_quality`, `deviation_bucket`, `nav_context` baru muncul **setelah** app (build yang sudah mengirim event itu) pernah mengirim data. Sambil menunggu: ketik **manual** nama parameter di kolom (huruf kecil, contoh `premium_quality` bukan `premiumQuality`). Verifikasi: **Firebase → Analytics → Events** → klik nama peristiwa → lihat daftar parameter sampel.

## Setelah 24–48 jam

Kirim beberapa peristiwa dari app (staging/production), lalu di **Explore** cek apakah dimensi kustom sudah terisi. Jika kosong: cek ejaan **parameter peristiwa** harus sama dengan kolom “Parameter” di Firebase (Analytics → Events → klik peristiwa → lihat parameter contoh).
