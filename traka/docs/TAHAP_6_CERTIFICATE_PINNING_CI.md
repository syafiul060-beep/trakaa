# Tahap 6: Certificate Pinning & CI/CD

## Ringkasan

Tahap 6 mencakup dua bagian:
1. **Certificate Pinning** – Mengamankan koneksi ke Traka API dari man-in-the-middle attack
2. **CI/CD** – Automated builds dan tests di Codemagic

---

## 1. Certificate Pinning

### Implementasi

- Package: `http_certificate_pinning: ^3.0.1` di `pubspec.yaml`
- Konfigurasi: `TrakaApiConfig.certificateSha256Fingerprint` dari env `TRAKA_API_CERT_SHA256`
- `TrakaApiService` memakai `SecureHttpClient` saat `isCertificatePinningEnabled == true`

### Kondisi Aktif

Pinning hanya aktif jika:
- `TRAKA_USE_HYBRID=true`
- `TRAKA_API_BASE_URL` terisi
- `TRAKA_API_CERT_SHA256` tidak kosong

### Dokumentasi Detail

Lihat `docs/SETUP_CERTIFICATE_PINNING.md` untuk cara mendapatkan fingerprint dan konfigurasi build.

---

## 2. CI/CD (Codemagic)

### Workflows

| Workflow | Fungsi |
|----------|--------|
| `traka-test` | Jalankan unit test saja (tanpa build) |
| `traka-ios-verify` | Verifikasi build iOS (no codesign) |
| `traka-ios-adhoc` | Build IPA Ad-hoc untuk tes di iPhone |
| `traka-ios` | Build IPA untuk App Store |
| `traka-android-verify` | Verifikasi build Android (APK debug) |

### Test di Semua Build

- `traka-test`: `flutter test`
- `traka-ios-verify`: `flutter test` + `flutter build ios --release --no-codesign`
- `traka-ios`: `flutter test` + build IPA
- `traka-android-verify`: `flutter test` + `flutter build apk --debug`

### Verifikasi Lokal

```bash
flutter test
```

Semua 48 unit test harus lulus sebelum merge.
