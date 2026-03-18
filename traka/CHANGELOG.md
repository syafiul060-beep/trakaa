# Changelog Traka

Semua perubahan penting aplikasi Traka didokumentasikan di sini.

---

## [1.0.6] - 2025

### Keamanan

- Gmail App Password di Cloud Functions tidak lagi di-hardcode; wajib via Environment Variables (GMAIL_EMAIL, GMAIL_APP_PASSWORD)
- Rate limit kode verifikasi registrasi: maksimal 3 kirim per email per 15 menit

### Fitur

- Opsi panggilan telepon biasa di chat (fallback jika voice call tidak tersedia atau driver/penumpang punya nomor di profil)
- Channel notifikasi pembayaran untuk Lacak Driver, Kontribusi, dll.
- Riwayat pembayaran kontribusi driver di Payment History
- Dashboard pendapatan driver di profil: pendapatan (hari ini, minggu ini, total), potongan kontribusi, pelanggaran, dan sisa belum dibayar
- Laporan pendapatan per bulan (terperinci seperti mutasi bank) dengan unduh PDF
- PDF laporan diverifikasi oleh Aplikasi Traka (untuk keperluan pengajuan kredit bank)

### Perbaikan

- Error handling FCM (background/foreground) lebih robust
- Notifikasi pembayaran berhasil ditampilkan setelah IAP verified

### Testing (sementara nonaktif)

- Deteksi lokasi palsu (fake GPS) dimatikan untuk uji coba versi 1.0.6

---

## [1.0.5] - 2025

### Perbaikan

- **Mode malam (dark mode):**
  - Pilihan lokasi tujuan (autocomplete) di form penumpang dan driver kini terbaca jelas
  - Teks tarif dan biaya di chat lebih terbaca di mode malam
  - Indikator rekaman pesan suara menyesuaikan tema gelap
  - Profile driver & penumpang: menu card dan sheet pakai warna tema
  - Data kendaraan: form dan dropdown pakai warna tema
  - Penumpang screen: driver sheet, bottom nav, search bar, loading overlay
  - Map: kontrol zoom dan tipe peta pakai warna tema

### Keamanan

- Deteksi fake GPS diperluas ke flow kritis: lokasi penumpang, kesepakatan harga, pesan, scan barcode
- Device ID untuk verifikasi login dan cegah spam

---

## [1.0.4] - 2025

### Fitur

- Panggilan suara (voice call) antara driver dan penumpang setelah kesepakatan harga
- Pesan suara di chat (rekam dan kirim seperti WhatsApp)
- Jadwal rute driver: atur jadwal per tanggal, tujuan awal/akhir, jam keberangkatan
- Cari jadwal: pesan travel berdasarkan jadwal driver
- Lacak Driver & Lacak Barang (in-app purchase)
- Scan barcode penumpang (driver) dan barcode driver (penumpang) untuk konfirmasi jemput/sampai tujuan
- Tarif per km: perhitungan dari titik jemput sampai titik turun
- Kontribusi driver setelah melayani penumpang
- Force update: notifikasi update wajib dari Play Store
- Promo dan riwayat pembayaran

### Perbaikan

- Perbaikan stabilitas dan pengalaman pengguna
- Debug print dibungkus kDebugMode

---

## [1.0.3] dan sebelumnya

- Fitur dasar: travel, kirim barang, chat, verifikasi wajah
- Login OTP email
- Onboarding
- Data Order, Lacak Driver, Lacak Barang
