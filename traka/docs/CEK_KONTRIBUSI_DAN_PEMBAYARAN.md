# Alur Kontribusi Driver, Lacak Driver, dan Lacak Barang

Dokumen ini merangkum alur pembayaran yang **sama** untuk ketiga fitur: Kontribusi Driver, Lacak Driver, dan Lacak Barang.

---

## Alur Umum (Sama untuk Semua)

```
User ingin akses fitur
        ↓
Cek: sudah bayar?
        ↓
   ┌────┴────┐
   │         │
  Ya        Tidak
   │         │
   ↓         ↓
Langsung   Halaman Bayar
ke tujuan  (Payment Screen)
           │
           ↓
      Google Play IAP
           │
           ↓
      Cloud Function verifikasi
           │
           ↓
      Update data (order/users)
           │
           ↓
      Navigasi ke tujuan / selesai
```

---

## Perbandingan Tiga Fitur

| Langkah | Kontribusi Driver | Lacak Driver | Lacak Barang |
|---------|-------------------|--------------|---------------|
| **Pemakai** | Driver | Penumpang | Pengirim atau Penerima |
| **Trigger** | Banner "Bayar kontribusi" (mustPayContribution) | Tombol "Lacak Driver" di Data Order | Tombol "Lacak Barang" di Data Order |
| **Cek sudah bayar** | `totalRupiah == 0` (paid up to date) | `passengerTrackDriverPaidAt != null` | `passengerLacakBarangPaidAt` atau `receiverLacakBarangPaidAt != null` |
| **Halaman bayar** | `ContributionDriverScreen` | `LacakDriverPaymentScreen` | `LacakBarangPaymentScreen` |
| **Product ID** | `traka_driver_dues_*` (7500–50000) | `traka_lacak_driver_3000` | `traka_lacak_barang_10k` / `15k` / `25k` (tier provinsi) |
| **Cloud Function** | `verifyContributionPayment` | `verifyPassengerTrackPayment` | `verifyLacakBarangPayment` |
| **Data di-update** | `users/{uid}` (contribution*PaidUpToRupiah) | `orders/{id}` → `passengerTrackDriverPaidAt` | `orders/{id}` → `passengerLacakBarangPaidAt` / `receiverLacakBarangPaidAt` |
| **Setelah bayar** | Pop ke Beranda driver | Navigasi ke `CekLokasiDriverScreen` | Navigasi ke `CekLokasiBarangScreen` |

---

## Detail per Fitur

### 1. Kontribusi Driver

**Aturan:** Driver wajib bayar kontribusi jika:
1. Sudah menyelesaikan rute (klik **Selesai Bekerja**)
2. Di dalam rute ada penumpang atau kirim barang yang **sudah selesai/sampai tujuan**

**Rute tidak disimpan** jika driver Selesai Bekerja tanpa ada penumpang/barang selesai (tidak ada kontribusi, tidak masuk Riwayat Rute).

Setelah bayar: rute ditandai **Lunas** di Riwayat Rute (Data Order > tab Riwayat Rute), aplikasi normal kembali (chat, kirim pesan, dll. aktif).

- **Sumber kewajiban:** `route_sessions` (rute belum lunas), `totalBarangContributionRupiah`, `outstandingViolationFee` di `users/{uid}`
- **Notifikasi:** FCM "Bayar kontribusi" saat kontribusi naik (`onOrderUpdatedScan`, `onUserPaymentDuesUpdate`)
- **Produk:** `traka_driver_dues_7500` s/d `traka_driver_dues_50000` (pilih nominal ≥ total kewajiban)

### 2. Lacak Driver

- **Sumber:** Order travel, penumpang ingin lacak posisi driver
- **Produk:** `traka_lacak_driver_3000` (default Rp 3.000, bisa diubah di Admin)
- **Field order:** `passengerTrackDriverPaidAt`

### 3. Lacak Barang

- **Sumber:** Order kirim barang, pengirim/penerima ingin lacak posisi barang
- **Produk:** `traka_lacak_barang_10k` (dalam provinsi), `15k` (beda provinsi), `25k` (>1 provinsi)
- **Field order:** `passengerLacakBarangPaidAt` (pengirim), `receiverLacakBarangPaidAt` (penerima)

---

## Notifikasi Kontribusi ke Driver

### Kapan driver dapat notifikasi "Bayar kontribusi"?

1. **Travel selesai:** `passengerScannedAt` di-set (scan atau auto-complete) → `onOrderUpdatedScan` → increment `totalTravelContributionRupiah` → FCM
2. **Kirim barang selesai:** `receiverScannedAt` di-set → increment `totalBarangContributionRupiah` → FCM
3. **Backup:** `users/{uid}` di-update (kontribusi naik) → `onUserPaymentDuesUpdate` → FCM

### Syarat notifikasi terkirim

- Driver punya `fcmToken` di `users/{uid}`
- Channel `traka_payment_channel` dibuat di app
- Untuk travel: order punya `tripTravelContributionRupiah` > 0

### Debug

- Firebase Console → Functions → Logs: cek `sendPaymentReminderFcm error` atau `fcmToken kosong`
- Pastikan driver sudah login dan app pernah dibuka

---

## Referensi

- Daftar produk Play Console: `docs/UPDATE_HARGA_GOOGLE_BILLING.md`
- Sinkron Admin: field di `app_config/settings` harus sesuai dengan produk Play
