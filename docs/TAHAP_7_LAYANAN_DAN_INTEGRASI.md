# Tahap 7: Layanan & Integrasi – phoneNumber Primary (Selesai)

Layanan yang query user by email/phone disesuaikan agar **phoneNumber** didukung sebagai identifier utama.

---

## Perubahan

### 1. OrderService.findUserByEmailOrPhone

**File**: `lib/services/order_service.dart`

- Tambah helper `_normalizePhoneE164` untuk normalisasi nomor Indonesia
- Perbaikan query phone: coba format asli + E.164 (0812.., 812.., 62812..)
- Pencarian penerima Kirim Barang sekarang lebih robust untuk berbagai format input

### 2. AccountDeletionService.findUserByPhone

**File**: `lib/services/account_deletion_service.dart`

- Tambah `findUserByPhone(phoneE164)` untuk query by phoneNumber
- `findUserByEmail` tetap untuk legacy
- Berguna untuk cek akun deleted by phone (jika diperlukan nanti)

### 3. Layanan lain (tidak diubah)

| Layanan | Status |
|---------|--------|
| **driver_contact_service** | Sudah pakai phoneNumbers, checkRegisteredDrivers |
| **registered_contacts_service** | Sudah pakai phoneNumbers |
| **driver_transfer_service** | Validasi email+phone; email kosong OK untuk Phone Auth |
| **chat_service** | Baca phoneNumber dari user doc |
| **verification_service** | Sudah cek phoneNumber |

---

## Catatan: Driver Transfer (tanpa password)

`DriverTransferService.applyDriverScanTransfer` **tidak lagi** memakai password. Cukup scan barcode ke driver yang dioper; driver yang login sudah terverifikasi. Kompatibel dengan Phone Auth (tidak perlu email+password).

---

## File yang diubah

- `lib/services/order_service.dart` – normalisasi phone, perbaikan query
- `lib/services/account_deletion_service.dart` – tambah `findUserByPhone`

---

## Status

- [x] Tahap 7 selesai
- [ ] Uji cari penerima Kirim Barang dengan no. telepon (berbagai format)
- [ ] Lanjut [Tahap 8: Testing & Deploy](TAHAP_8_TESTING_DAN_DEPLOY.md)
