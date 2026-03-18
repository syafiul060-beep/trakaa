# Tahap 3: device_rate_limit → Cloud Function

## Ringkasan

Collection `device_rate_limit` dipindahkan dari akses client langsung ke Cloud Function untuk keamanan lebih baik. Sebelumnya, Firestore rules mengizinkan `allow read, write: if true` (siapa saja bisa baca/tulis tanpa auth).

## Perubahan

### 1. Cloud Functions baru (functions/index.js)

- **checkLoginRateLimit** – Cek apakah device melebihi rate limit (max 10 gagal/jam)
- **recordLoginFailed** – Catat percobaan login gagal
- **recordLoginSuccess** – Reset rate limit saat login berhasil

### 2. DeviceSecurityService (lib/services/device_security_service.dart)

- `checkLoginRateLimit()` – Memanggil Cloud Function `checkLoginRateLimit` (bukan Firestore)
- `recordLoginFailed()` – Memanggil Cloud Function `recordLoginFailed`
- `recordLoginSuccess()` – Memanggil Cloud Function `recordLoginSuccess`

### 3. Firestore Rules (firestore.rules)

- `device_rate_limit` → `allow read, write: if false`
- Hanya Admin SDK di Cloud Function yang boleh akses

## Deployment

1. **Deploy Cloud Functions**:
   ```bash
   cd traka/functions
   npm install
   firebase deploy --only functions
   ```

2. **Deploy Firestore Rules**:
   ```bash
   firebase deploy --only firestore:rules
   ```

3. **Update App** – Build dan deploy versi baru aplikasi Flutter

## Urutan Deployment (PENTING)

1. Deploy Cloud Functions **lebih dulu**
2. Deploy Firestore Rules
3. Deploy aplikasi Flutter

Jika aplikasi di-update sebelum Cloud Functions di-deploy, login gagal akan tidak tercatat dan rate limit tidak berfungsi.

## Rollback

Jika ada masalah:
1. Revert Firestore rules: `device_rate_limit` → `allow read, write: if true`
2. Revert DeviceSecurityService ke Firestore langsung
3. Deploy ulang
