# Setup Verifikasi Pembayaran Google Play

Cloud Functions Traka sekarang memverifikasi purchase token ke Google Play Developer API sebelum menerima pembayaran.

## Konfigurasi

Tambahkan salah satu environment variable di Firebase Console > Functions > Environment variables:

### Opsi 1: JSON string (direkomendasikan untuk Cloud)
- **GOOGLE_PLAY_SERVICE_ACCOUNT_KEY**: Isi dengan JSON lengkap service account (private key, client_email, dll)

### Opsi 2: Path ke file (untuk emulator/local)
- **GOOGLE_PLAY_SERVICE_ACCOUNT_PATH**: Path ke file JSON service account

## Langkah Setup

1. Buka [Google Cloud Console](https://console.cloud.google.com/)
2. Pilih project yang terhubung ke Play Developer account
3. Enable **Google Play Android Developer API**
4. Buat Service Account: IAM & Admin > Service Accounts > Create
5. Buat key JSON untuk service account
6. Di [Play Console](https://play.google.com/console/) > Users and permissions > Invite new users
7. Tambahkan email service account dengan permission **View financial data**
8. Set environment variable di Firebase Functions dengan isi file JSON (sebagai string)

## Jika Belum Dikonfigurasi

Jika `GOOGLE_PLAY_SERVICE_ACCOUNT_KEY` dan `GOOGLE_PLAY_SERVICE_ACCOUNT_PATH` tidak diset, semua verifikasi pembayaran akan **gagal** (return `verified: false`). Ini sengaja untuk keamanan.
