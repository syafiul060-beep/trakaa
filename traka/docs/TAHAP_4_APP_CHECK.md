# Tahap 4: App Check Enforcement

## Ringkasan

App Check enforcement diaktifkan untuk Cloud Functions. Semua callable function sekarang memerlukan token App Check yang valid. Request dari app kloning atau client tidak resmi akan ditolak.

## Perubahan

**functions/index.js**:
- `ENFORCE_APP_CHECK = true` (sebelumnya `false`)

## Prasyarat

Sebelum deploy, pastikan:

1. **App Check sudah didaftar** di Firebase Console (Play Integrity untuk Android, App Attest untuk iOS)
2. **SHA-256** signing key sudah ditambahkan di App Check
3. **Debug token** sudah didaftar jika testing di emulator
4. **App release** sudah di-deploy dengan App Check aktif (main.dart)

## Deployment

```bash
cd traka/functions
firebase deploy --only functions
```

## Dampak

- **App resmi**: Berfungsi normal (token App Check otomatis dikirim)
- **App kloning**: Request ke Cloud Functions ditolak
- **Emulator tanpa debug token**: Request ditolak
- **Device tertentu** (custom ROM, dll): Mungkin gagal jika Play Integrity tidak tersedia

## Rollback

Jika banyak user gagal (misalnya device tertentu):

1. Edit `functions/index.js`: `ENFORCE_APP_CHECK = false`
2. Deploy: `firebase deploy --only functions`
3. Monitor metrik App Check di Firebase Console sebelum aktifkan lagi

## Verifikasi

Setelah deploy, test:
- Login (email & phone)
- Registrasi (request kode verifikasi)
- Lacak Driver / Lacak Barang payment
- Semua flow yang memanggil Cloud Functions
