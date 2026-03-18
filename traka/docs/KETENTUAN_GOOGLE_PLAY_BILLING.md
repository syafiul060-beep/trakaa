# Ketentuan Google Play Billing & Kesesuaian Traka

Dokumen ini merangkum ketentuan Google Play Billing dan kesesuaian implementasi Traka.

---

## 1. Alur Pembayaran Saat Ini

```
User bayar via Google Play
        ↓
purchaseStream emit PurchaseStatus.purchased
        ↓
App panggil Cloud Function (verifyContributionPayment, dll)
        ↓
Server verifikasi dengan Google Play API (purchases.products.get)
        ↓
Server update Firestore (users, orders, route_sessions, dll)
        ↓
App panggil completePurchase(purchase)  ← ACKNOWLEDGE (wajib)
        ↓
Tampilkan sukses, navigasi
```

---

## 2. Ketentuan Google Play yang Dipenuhi

### 2.1 Verifikasi Server-Side ✅

- Cloud Function memverifikasi `purchaseToken` via Android Publisher API
- File: `functions/lib/verifyGooglePlay.js`
- Cek `purchaseState === 0` (Purchased)

### 2.2 Acknowledge dalam 3 Hari ✅

- **Wajib:** Pembelian harus di-acknowledge dalam 3 hari, atau Google otomatis refund
- **Implementasi:** App memanggil `InAppPurchase.completePurchase(purchase)` setelah verifikasi server berhasil
- Berlaku untuk: Kontribusi, Lacak Driver, Lacak Barang, Pelanggaran

### 2.3 Urutan yang Benar ✅

1. Verifikasi server (pastikan pembelian valid)
2. Update data (grant content)
3. Acknowledge (completePurchase)

---

## 3. Perubahan yang Dilakukan (Maret 2025)

| File | Perubahan |
|------|-----------|
| `contribution_driver_screen.dart` | Tambah `await _iap.completePurchase(purchase)` setelah verify |
| `violation_pay_screen.dart` | Tambah `await _iap.completePurchase(purchase)` setelah verify |
| `lacak_driver_payment_screen.dart` | Tambah `await _iap.completePurchase(purchase)` setelah verify |
| `lacak_barang_payment_screen.dart` | Tambah `await _iap.completePurchase(purchase)` setelah verify |

**Tanpa completePurchase:** Pembelian akan di-refund otomatis oleh Google dalam 3 hari.

---

## 4. Pending Purchase Recovery ✅

- **Service:** `lib/services/pending_purchase_recovery_service.dart`
- **Fungsi:** Memulihkan pembelian tertunda (belum di-acknowledge) saat app dibuka setelah crash/tertutup.
- **Produk yang direcovery:** Kontribusi (`traka_driver_dues_*`), Pelanggaran (`traka_violation_fee_*`).
- **Lacak Driver & Lacak Barang:** Ditangani di layar pembayaran masing-masing (perlu orderId dari context).
- **Koordinasi:** `PaymentContextService` mencegah duplikasi saat layar pembayaran aktif.

---

## 5. Ketentuan Tambahan (Opsional)

### 5.1 Billing Library 7

- **Deadline:** 31 Agustus 2025 (extensi sampai 1 Nov 2025)
- Flutter `in_app_purchase` package menggunakan Billing Library native
- Cek versi Billing Library di `android/build.gradle` / dependencies
- Migrasi: https://developer.android.com/google/play/billing/migrate-gpblv7

### 5.2 Real-time Developer Notifications (RTDN)

- Google merekomendasikan RTDN agar server mendapat notifikasi pembelian
- Berguna untuk: pembelian saat app tertutup, sinkronisasi multi-device
- Memerlukan: Cloud Pub/Sub, endpoint webhook
- **Status Traka:** Belum diimplementasi. Alur app-initiated (app dapat purchase → app panggil server) sudah memadai untuk kasus umum.

---

## 6. Referensi

- [Integrate Google Play with your server backend](https://developer.android.com/google/play/billing/backend)
- [Acknowledge purchases](https://developer.android.com/google/play/billing/integrate#acknowledge)
- [Flutter in_app_purchase completePurchase](https://pub.dev/documentation/in_app_purchase/latest/in_app_purchase/InAppPurchase/completePurchase.html)
