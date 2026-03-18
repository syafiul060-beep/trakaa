# Cek Aplikasi Traka – Laporan Lengkap

Tanggal: 28 Feb 2026

---

## 1. Status Build & Test

| Item | Status |
|------|--------|
| **Unit test** | ✅ 48 tests passed |
| **Linter** | ✅ No errors |
| **Flutter analyze** | ⏳ (dijalankan di background) |

---

## 2. Konfigurasi Fitur (Production)

| Fitur | Flag | Nilai | Keterangan |
|-------|------|-------|------------|
| Pembayaran Lacak Driver | `kLacakDriverPaymentRequired` | `true` | Penumpang wajib bayar |
| Pembayaran Lacak Barang | `kLacakBarangPaymentRequired` | `true` | Pengirim/penerima wajib bayar |
| Kontribusi driver | `kContributionEnabled` | `true` | Driver wajib bayar kontribusi |
| Deteksi fake GPS | `kDisableFakeGpsCheck` | `false` | Deteksi aktif (blokir lokasi palsu) |

---

## 3. Pengecualian via Admin (tanpa ubah program)

| Daftar | Firestore | Fungsi |
|--------|-----------|--------|
| Driver Bebas Kontribusi | `app_config/contribution_exempt_drivers` | Driver tidak bayar kontribusi |
| Penumpang Bebas Lacak | `app_config/lacak_exempt_users` | Tidak bayar Lacak Driver & Barang |
| Pengguna Fake GPS Allowed | `app_config/fake_gps_allowed_users` | Boleh pakai lokasi palsu |

---

## 4. Unit Test Coverage

| File | Cakupan |
|------|---------|
| app_constants_test | AppConstants |
| app_logger_test | AppLogger |
| device_security_service_test | DeviceSecurityResult, DeviceSecurityService |
| order_model_test | OrderModel |
| order_service_test | OrderService (status, radius, findUser, getRecentReceivers) |
| retry_utils_test | RetryUtils |
| route_utils_test | RouteUtils |
| validation_utils_test | ValidationUtils |
| vehicle_plat_service_test | VehiclePlatService |
| widget_test | Test framework |

---

## 5. TODO / Catatan

- Tier 3 Lacak Barang: Sudah diimplementasi (beda pulau = tier 3, beda provinsi sama pulau = tier 2).

---

## 6. Versi & Dependencies

- **App version**: 1.0.6+7
- **SDK**: ^3.10.7
- **Firebase**: core, auth, firestore, functions, storage, analytics, crashlytics
- **Google Maps**: google_maps_flutter
- **IAP**: in_app_purchase
- **Certificate pinning**: http_certificate_pinning ^3.0.1

---

## 7. CI/CD (Codemagic)

| Workflow | Fungsi |
|----------|--------|
| traka-test | Unit test saja |
| traka-ios-verify | Build iOS (no codesign) |
| traka-ios-adhoc | IPA Ad-hoc |
| traka-ios | IPA App Store |
| traka-android-verify | Build Android APK debug |

---

## 8. Ringkasan

Aplikasi dalam kondisi siap production:

- Semua fitur pembayaran (Lacak Driver, Lacak Barang, Kontribusi) aktif
- Deteksi fake GPS aktif
- Pengecualian bisa diatur via Admin Settings
- Unit test lulus, tidak ada error linter
- CI/CD terkonfigurasi untuk iOS dan Android
