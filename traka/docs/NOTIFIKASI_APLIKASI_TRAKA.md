# Notifikasi aplikasi Traka — referensi & tahapan

Dokumen ini merangkum **tahap 1–4** (dokumentasi, UI pengaturan, polish, roadmap) dan mengarahkan ke file kode terkait.

---

## Tahap 1 — Dokumentasi & platform

| Topik | Isi |
|--------|-----|
| **Android** | Notifikasi **lokal** (`flutter_local_notifications`): channel terpisah — lihat `lib/services/route_notification_service.dart` (Rute Aktif, Driver Mendekati, Lacak Barang, Pembayaran, Pengingat Jadwal). |
| **iOS** | Banyak notifikasi lokal **jarak/rute** hanya dijalankan jika `Platform.isAndroid` di `RouteNotificationService`; **push** (FCM) tetap bisa jika izin diberikan. |
| **Push server** | `traka/functions/index.js` — chat, order, scan, panggilan, pengingat kontribusi/jadwal, dll. |

---

## Tahap 2 — Pengaturan di app

- **Profil** (penumpang & driver) → **Notifikasi** → layar `lib/screens/notification_settings_screen.dart`: penjelasan channel + push, tombol **Buka pengaturan notifikasi** (`AppSettings.openAppSettings(type: AppSettingsType.notification)` — Android & iOS 16+).
- **Analytics:** `notification_settings_open`, `notification_settings_system_tap` (`AppAnalyticsService`).
- **Analytics — notifikasi lokal jarak:** saat banner proximity benar-benar ditampilkan → `local_proximity_notif_shown` dengan parameter `flow` (`passenger_pickup` | `receiver_goods`) dan `band` (`500m` | `1km`). Dipanggil dari `passenger_proximity_notification_service.dart` & `receiver_proximity_notification_service.dart`.

---

## Tahap 3 — Polish & QA

- **Judul notifikasi jarak:** notifikasi “driver dekat” memakai judul **“Driver mendekati”** (selaras dengan nama channel), bukan hanya “Traka”.
- **Uji regresi:** skenario di [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md) bagian **N**.

**Saran lanjutan (opsional, belum wajib di kode):** prioritas channel **chat** FCM bisa diturunkan untuk pesan teks biasa; pertahankan **high** untuk order/panggilan — sesuaikan di Functions jika produk setuju.

---

## Tahap 4 — Roadmap (server-side proximity)

- **Saat ini:** notifikasi jarak penumpang memakai **stream posisi driver** di perangkat penumpang (`passenger_proximity_notification_service.dart`) + update `driver_status`.
- **Opsi masa depan:** Cloud Function / job yang mengirim FCM saat jarak melewati ambang jika penumpang **tidak** membuka app — **biaya**, **kompleksitas**, dan kebijakan privasi perlu kaji terpisah.

---

## Dampak performa (ringkas)

- **Notifikasi lokal + analytics** proximity: dipicu **paling banyak beberapa kali per perjalanan** (bukan loop tiap detik). Overhead dominan tetap **stream posisi driver** + **write `driver_status`** — lihat tier di [`NOTIFIKASI_JARAK_PENUMPANG_DRIVER.md`](NOTIFIKASI_JARAK_PENUMPANG_DRIVER.md).
- **Analytics** `local_proximity_notif_shown` mengikuti frekuensi notifikasi; Firebase Analytics meng-buffer event — tidak setara dengan tambahan polling lokasi.

## Deploy setelah perubahan notifikasi

Tergantung **apa** yang diubah:

| Yang berubah | Apa yang perlu di-deploy |
|--------------|---------------------------|
| **Kode Flutter** (`lib/services/route_notification_service.dart`, proximity, `notification_settings_screen.dart`, channel, teks, analytics client, dll.) | **Rilis app baru** — build AAB/APK dan upload ke Play Store (internal / production). Ikuti [`BUILD_PLAY_STORE.md`](BUILD_PLAY_STORE.md). Pengguna harus **update app** agar perubahan aktif. |
| **Cloud Functions** (`traka/functions/`, mis. payload FCM, prioritas, trigger chat/order) | Dari folder project Firebase (biasanya `traka/`): `firebase deploy --only functions`. Tidak perlu rilis app jika hanya server berubah — **kecuali** client juga mengandalkan field/perilaku baru. Lihat juga [`ENV_VARS_FUNCTIONS.md`](ENV_VARS_FUNCTIONS.md) jika ada env var. |
| **Firestore / Storage rules** (jarang untuk notifikasi murni) | `firebase deploy --only firestore:rules` atau `storage:rules` sesuai kebutuhan. |
| **Hanya dokumentasi** | Tidak perlu deploy. |

**Ringkas:** notifikasi **lokal** = wajib **build & upload app**. **Push FCM** dari Functions = **`firebase deploy --only functions`**. Keduanya bisa dibutuhkan bila Anda mengubah server **dan** cara app menampilkan/menangani notifikasi.

## Tautan terkait

- Jarak driver–penumpang & tier update lokasi: [`NOTIFIKASI_JARAK_PENUMPANG_DRIVER.md`](NOTIFIKASI_JARAK_PENUMPANG_DRIVER.md)  
- Perbaikan UI/performa (notifikasi): [`PERBAIKAN_UI_UX_PERFORMA_2025-03.md`](PERBAIKAN_UI_UX_PERFORMA_2025-03.md)
