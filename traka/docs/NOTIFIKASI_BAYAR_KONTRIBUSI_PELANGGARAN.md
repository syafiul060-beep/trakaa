# Notifikasi Bayar Kontribusi & Pelanggaran

Dokumentasi notifikasi push untuk mengingatkan pengguna membayar kontribusi dan pelanggaran.

## Ringkasan

Sebelumnya tidak ada notifikasi push saat pengguna punya kewajiban bayar. Sekarang Cloud Function mengirim FCM saat:

1. **Driver dapat kontribusi** – setelah order travel/kirim barang selesai
2. **Driver/penumpang dapat pelanggaran** – setelah konfirmasi otomatis (tanpa scan barcode)

## Alur Notifikasi

### Kontribusi Driver

- **Trigger travel:** `onRouteSessionCreated` – saat rute selesai (driver "Berhenti Kerja") dan `route_sessions` punya `contributionRupiah` > 0
- **Trigger barang:** `onUserPaymentDuesUpdate` – saat `totalBarangContributionRupiah` di-increment
- **Notifikasi:** "Bayar kontribusi" – "Anda punya kewajiban bayar kontribusi. Buka aplikasi untuk membayar."

### Pelanggaran (Driver & Penumpang)

- **Trigger:** `onUserPaymentDuesUpdate` – saat `users/{uid}` di-update dan `outstandingViolationFee` bertambah
- **Kondisi:** App menulis `outstandingViolationFee` (dari auto-confirm pickup/complete)
- **Notifikasi:** "Bayar pelanggaran" – "Anda punya pelanggaran yang perlu dibayar. Buka aplikasi untuk membayar."

## Channel Notifikasi

- **Android:** `traka_payment_channel` (dibuat di `RouteNotificationService.init()`)
- **Prioritas:** high

## Deploy Cloud Function

Setelah perubahan di `functions/index.js`, deploy:

```bash
cd traka/functions
npm run deploy
```

Atau deploy fungsi tertentu:

```bash
firebase deploy --only functions:onOrderUpdatedScan,functions:onUserPaymentDuesUpdate
```

## Cek di Aplikasi

1. **Driver kontribusi:** Buka Beranda driver → jika `mustPayContribution` true, banner oranye "Bayar kontribusi" tampil
2. **Driver pelanggaran:** Masuk ke total kontribusi (bayar via ContributionDriverScreen)
3. **Penumpang pelanggaran:** Saat Cari travel, redirect ke ViolationPayScreen jika `outstandingViolationFee` > 0
