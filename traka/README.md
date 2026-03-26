# Traka

Aplikasi travel dan pengiriman barang terpercaya di Kalimantan. Pesan tiket travel atau kirim barang dengan mudah.

## Fitur Utama

- **Travel**: Cari jadwal travel, pesan tiket, lacak driver
- **Kirim Barang**: Kirim barang antar kota dengan driver terpercaya
- **Chat & Panggilan Suara**: Komunikasi langsung dengan driver
- **Verifikasi**: Foto wajah, KTP/SIM, nomor telepon untuk keamanan

## Struktur Proyek

```
lib/
├── screens/      # Halaman utama (penumpang, driver, chat, profil, dll.)
├── services/     # Logika bisnis (order, lokasi, Firebase, dll.)
├── models/       # Model data (Order, User, dll.)
├── widgets/      # Komponen UI reusable
├── l10n/         # Lokalisasi (Indonesia, English)
├── theme/        # Tema & responsive
└── config/       # Konfigurasi aplikasi
```

## Persiapan

1. **Flutter** (SDK ^3.10.7)
2. **Firebase** – project sudah dikonfigurasi
3. **Google Maps API** – untuk map dan directions

## Menjalankan

```bash
flutter pub get
flutter run
```

**Mode hybrid** (API backend + dual-write Firestore): dari folder `traka`, `.\scripts\run_hybrid.ps1` (Windows) — setara `--dart-define=TRAKA_API_BASE_URL=...` dan `TRAKA_USE_HYBRID=true`. Build Play Store: `.\scripts\build_hybrid.ps1 -Target appbundle` — lihat [`docs/BUILD_PLAY_STORE.md`](docs/BUILD_PLAY_STORE.md). Cek `/health` + Redis: `.\scripts\verify_api_health.ps1`. CI: job `build-hybrid-smoke` di `.github/workflows/traka_ci.yml`.

## Dokumentasi

- [Halaman web profil Traka](hosting/profil.html) — setelah deploy hosting: `/profil.html` (ilustrasi/brosur SVG + strip visual; tambah foto promo lewat [hosting/assets/README-PROFIL-GAMBAR.txt](hosting/assets/README-PROFIL-GAMBAR.txt))
- [Halaman lacak keluarga](hosting/track.html) — `/track.html?t=…` (peta + status; **Authentication → Sign-in method → Anonymous** harus aktif di Firebase agar pembacaan `driver_status` berhasil untuk pengunjung tanpa akun). Status `completed`/`cancelled` di dokumen `track_share_links` saat ini hanya terlihat jika nilai itu diperbarui di backend (mis. Function) — UI siap menampilkan layar selesai saat field tersebut berubah. **Kirim barang:** setelah update aturan `track_share_links` di Firestore, deploy **`firebase deploy --only firestore:rules`** sebelum/saat rilis app agar penerima yang membagikan link tetap lolos validasi create (field `passengerUid`/`receiverUid` mengacu ke pesanan, bukan UID pembuat link).
- [QA regresi alur utama](docs/QA_REGRESI_ALUR_UTAMA.md) – skenario manual sebelum rilis
- [QA regresi mode hybrid](docs/QA_HYBRID_REGRESI.md) – API + Firestore, order, driver status, jadwal, admin
- [Rute alternatif driver & matching penumpang](docs/ROUTING_ALTERNATIF_DRIVER_DAN_MATCH_PENUMPANG.md) – kapan garis biru/auto-switch, re-route, vs filter “cari driver”
- [Notifikasi jarak penumpang ↔ driver](docs/NOTIFIKASI_JARAK_PENUMPANG_DRIVER.md) – tanpa tap “arahkan”, live tracking saat agreed menunggu jemput
- [Notifikasi aplikasi (tahap 1–4)](docs/NOTIFIKASI_APLIKASI_TRAKA.md) – channel Android, push FCM, layar Profil → Notifikasi, roadmap
- [Perbaikan UI/UX & performa (ringkas)](docs/PERBAIKAN_UI_UX_PERFORMA_2025-03.md) – trace Firebase, bottom nav, tema dialog
- [Kebijakan blokir beranda & jenis order](docs/KEBIJAKAN_BLOKIR_BERANDA_DAN_ORDER.md) – travel vs kirim barang
- [Roadmap infrastruktur / skala](docs/ROADMAP_INFRASTRUKTUR_SKALA.md) – kapan WebSocket, dll.
- [Setup Config Lokal](../docs/CEGAH_API_KEY_TEREKSPOS.md#setup-untuk-developer-baru-setelah-clone-repo) – file config setelah clone (Keys.plist, firebase-config.js, dll)
- [Build dan Jalankan](docs/BUILD_DAN_JALANKAN.md) – troubleshooting build
- [Firebase Setup](docs/FIREBASE_DAN_SETUP.md) – konfigurasi Firebase
- [Deploy Firebase cepat](docs/FIREBASE_DEPLOY_CEPAT.md) – `firebase deploy` dari `traka/`, admin terpisah di `traka-admin/`, catatan Node 20 & `firebase-functions`
- [Google Maps](docs/SETUP_GOOGLE_MAPS.md) – API key Maps
- [Cloud Functions](docs/LANGKAH_SETUP_MANUAL.md) – setup Functions
- [Deploy Play Store](docs/BUILD_PLAY_STORE.md) – publish Android
- [Deploy iOS](docs/IOS_DEPLOY.md) – publish iOS

## Platform

- **Android**: Utama (min SDK 21)
- **iOS**: Didukung (setup di `docs/IOS_DEPLOY.md`)
