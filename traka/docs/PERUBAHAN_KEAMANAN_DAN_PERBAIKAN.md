# Ringkasan Perubahan Keamanan dan Perbaikan Traka

Dokumen ini merangkum semua perubahan yang telah diimplementasikan untuk jangka panjang.

## 1. Verifikasi Pembayaran Google Play (Cloud Functions)

**Sebelum:** Semua fungsi pembayaran menggunakan `verified = true` tanpa verifikasi.

**Sesudah:** Purchase token diverifikasi ke Google Play Developer API via `lib/verifyGooglePlay.js`.

**Fungsi yang diupdate:**
- `verifyContributionPayment`
- `verifyPassengerTrackPayment`
- `verifyLacakBarangPayment`
- `verifyViolationPayment`

**Setup:** Lihat [SETUP_GOOGLE_PLAY_VERIFICATION.md](SETUP_GOOGLE_PLAY_VERIFICATION.md)

---

## 2. Firestore Security Rules

**Perubahan:**
- **users:** `allow read: if request.auth != null` (sebelumnya `if true`)
- **verification_codes:** `allow read, write: if false` (akses hanya via Cloud Function)
- **device_accounts:** Baca/tulis dibatasi ke user yang punya data
- **driver_status:** `allow read: if request.auth != null`

**Cloud Functions baru untuk alur tanpa auth:**
- `checkEmailExists` - cek email terdaftar (login)
- `checkPhoneExists` - cek nomor HP terdaftar (forgot password)
- `checkRegistrationAllowed` - cek device boleh registrasi
- `verifyRegistrationCode` - verifikasi kode email (baca + hapus jika valid)

---

## 3. Traka API

**Rate limiting:** 100 request/15 menit per IP

**CORS:** Batasi origin via env `ALLOWED_ORIGINS` (comma-separated)

**Input validation:** 
- `validation.js` - sanitizeString, isValidUid, isValidLatLng
- Validasi latitude/longitude di POST /driver/location
- Validasi uid di GET /users/:uid

**Redis:** Ganti `KEYS *` dengan `SCAN` (scanKeys) untuk production

---

## 4. Flutter App

**Provider:** 
- Tambah `provider` package
- `AppConfigProvider` untuk tarif per km
- `app_constants.dart` - konstanta default

**Image compression:** 
- `flutter_image_compress` - kompresi sebelum upload
- `ImageCompressionService.compressForUpload()` sudah dipakai di profile, face verification

**Cloud Functions:** 
- `DeviceSecurityService.checkRegistrationAllowed` → panggil Cloud Function
- `register_screen` → `verifyRegistrationCode` menggantikan baca Firestore
- `login_screen` → `checkEmailExists` untuk invalid-credential
- `forgot_password_screen` → `checkPhoneExists` sebelum verifyPhoneNumber

---

## 5. Dokumentasi

- `SETUP_GOOGLE_PLAY_VERIFICATION.md` - Setup verifikasi pembayaran
- `traka-api/docs/API.md` - Dokumentasi API

---

## Langkah Deploy

1. **Firebase Functions:** 
   - `cd traka/functions && npm install && firebase deploy --only functions`
   - Set env: `GOOGLE_PLAY_SERVICE_ACCOUNT_KEY` atau `GOOGLE_PLAY_SERVICE_ACCOUNT_PATH`

2. **Firestore Rules:** 
   - `firebase deploy --only firestore:rules`

3. **Traka API:** 
   - Set env: `ALLOWED_ORIGINS` untuk production
   - Deploy ke hosting (Railway, Render, dll)

4. **Flutter App:** 
   - `flutter pub get`
   - Build dan deploy ke Play Store
