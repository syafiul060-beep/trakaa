# Persiapan Update Play Store – Traka

Dokumen ini berisi teks deskripsi dan checklist untuk update aplikasi Traka di Google Play Store.

**Versi saat ini di Play Store:** 1.0.8  
**Versi siap upload:** 1.0.9+10 (dari `pubspec.yaml`)

---

## 1. Deskripsi Singkat (Short Description)

**Maksimal 80 karakter.**

```
Travel & kirim barang Kalimantan. Pesan, lacak driver real-time, chat, bayar via Google Play.
```

**Alternatif:**
```
Pesan travel & kirim barang. Lacak driver, chat, bayar aman via Google Play. #TravelKalimantan
```

---

## 2. Deskripsi Lengkap (Full Description)

**Maksimal 4.000 karakter.**

```
Traka – Aplikasi travel dan pengiriman barang terpercaya di Kalimantan.

PESAN TRAVEL
• Cari driver aktif sesuai rute Anda
• Kesepakatan harga langsung dengan driver via chat
• Lacak driver real-time di peta (bayar Rp 3.000)
• Scan barcode saat dijemput dan sampai tujuan
• Rating & review setelah perjalanan selesai

KIRIM BARANG
• Pilih jenis: dokumen atau kargo
• Tunjuk penerima (kontak atau link)
• Lacak barang real-time (bayar via Google Play)
• Penerima scan barcode saat barang diterima

FITUR CHAT
• Chat teks, gambar, suara, dan video dengan driver
• Panggilan suara (radius dekat)
• Notifikasi real-time

UNTUK DRIVER
• Pilih rute dan mulai kerja
• Terima order dari penumpang/pengirim
• Navigasi ke titik jemput dan tujuan
• Bayar kontribusi via Google Play
• Lihat pendapatan & riwayat pembayaran

KEAMANAN
• Verifikasi wajah saat daftar/login device baru
• 1 device per akun
• Deteksi fake GPS

PEMBAYARAN
Semua pembayaran (lacak driver, lacak barang, kontribusi driver, denda) via Google Play Billing – aman dan terverifikasi.

Download Traka – Travel Kalimantan, satu aplikasi untuk perjalanan dan pengiriman.
```

---

## 3. What's New (Changelog)

**Untuk kolom "What's New" di Play Console. Maksimal 500 karakter.**

**Versi 1.0.9 (update dari 1.0.8):**
```
• Perbaikan navigasi antar halaman (Riwayat Pembayaran, Pendapatan & Potongan)
• Link Riwayat Pembayaran di Data Order (penumpang & driver)
• Format harga dengan pemisah ribuan
• Tooltip Lacak Barang menampilkan harga dari konfigurasi
• Perbaikan kecil dan lokalisasi
```

**Alternatif (lebih singkat):**
```
• Navigasi lebih mudah ke Riwayat Pembayaran dan Pendapatan
• Perbaikan tampilan harga
• Perbaikan kecil dan stabilitas
```

---

## 4. Checklist Rilis Update

### 4.1 Sebelum Build

- [ ] **Versi** – Saat ini: `1.0.9+10` (Play Store masih 1.0.8). Untuk rilis berikutnya naikkan di `pubspec.yaml`
  - Contoh: `1.0.9+10` → `1.0.10+11` (versionName + versionCode)
- [ ] **Changelog** – Siapkan teks "What's New" (lihat bagian 3)
- [ ] **Cloud Functions** – Deploy jika ada perubahan: `firebase deploy --only functions`
- [ ] **App Config** – Cek `app_config/settings` di Firestore (harga, tier, dll.)

### 4.2 Build & Signing

- [ ] **Android**
  - `flutter build appbundle` (untuk Play Store)
  - Pastikan signing config benar di `android/app/build.gradle.kts`
- [ ] **iOS** (jika rilis ke App Store)
  - `flutter build ipa`
  - Pastikan provisioning profile & certificate valid

### 4.3 Testing Sebelum Upload

- [ ] **Login** – Device sama (password), device baru (OTP ± wajah)
- [ ] **Pesan travel** – Cari → pesan → kesepakatan → jemput → selesai
- [ ] **Kirim barang** – Pengirim → penerima setuju → driver → selesai
- [ ] **Chat** – Teks, gambar, suara, notifikasi
- [ ] **Lacak driver** – Bayar → peta real-time
- [ ] **Lacak barang** – Bayar → peta real-time
- [ ] **Pembayaran** – Kontribusi driver, pelanggaran (Google Play)
- [ ] **Riwayat** – Riwayat Pembayaran, Pendapatan & Potongan
- [ ] **Voice call** – Panggilan suara penumpang–driver
- [ ] **Force update** – Jika ada, pastikan berjalan

### 4.4 Play Console

- [ ] **Upload** – Upload AAB ke Play Console (Production / Internal testing / Closed testing)
- [ ] **Release notes** – Isi "What's New" (bahasa Indonesia & Inggris jika perlu)
- [ ] **Screenshot** – Update jika ada perubahan UI
- [ ] **Content rating** – Tidak perlu diubah jika tidak ada perubahan konten
- [ ] **Data safety** – Pastikan form Data safety sesuai (lokasi, kontak, pembayaran, dll.)
- [ ] **Target audience** – Sesuaikan jika perlu

### 4.5 Setelah Rilis

- [ ] **Monitoring** – Cek Crashlytics, Firebase Performance
- [ ] **Review** – Pantau rating & review pengguna
- [ ] **Dokumentasi** – Update `PLAY_CONSOLE_WARNINGS.md` jika ada peringatan baru

---

## 5. Data Safety (Ringkasan untuk Form Play Console)

| Data | Dikumpulkan | Dibagikan | Tujuan |
|------|-------------|-----------|--------|
| Lokasi | Ya | Driver (saat order aktif) | Lacak, navigasi |
| Kontak | Ya (nomor HP) | Tidak | Login, verifikasi |
| Email | Opsional | Tidak | Login alternatif |
| Foto | Ya (profil, verifikasi) | Driver (saat order) | Verifikasi, identitas |
| Informasi pembelian | Ya | Google | Pembayaran via Play Billing |
| ID perangkat | Ya | Tidak | Keamanan, 1 device per akun |

*Sesuaikan dengan form Data safety di Play Console.*

---

## 6. Kontak & Support

Pastikan di Play Console:
- **Email developer** – Terisi dan aktif
- **Privacy policy URL** – Valid
- **Support email** – Untuk pengguna menghubungi tim

---

*Dokumen ini dibuat untuk memudahkan proses update Traka di Google Play Store. Sesuaikan versi, tanggal, dan detail sesuai rilis Anda.*
