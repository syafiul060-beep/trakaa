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

## Dokumentasi

- [Build dan Jalankan](docs/BUILD_DAN_JALANKAN.md) – troubleshooting build
- [Firebase Setup](docs/FIREBASE_DAN_SETUP.md) – konfigurasi Firebase
- [Google Maps](docs/SETUP_GOOGLE_MAPS.md) – API key Maps
- [Cloud Functions](docs/LANGKAH_SETUP_MANUAL.md) – setup Functions
- [Deploy Play Store](docs/BUILD_PLAY_STORE.md) – publish Android
- [Deploy iOS](docs/IOS_DEPLOY.md) – publish iOS

## Platform

- **Android**: Utama (min SDK 21)
- **iOS**: Didukung (setup di `docs/IOS_DEPLOY.md`)
