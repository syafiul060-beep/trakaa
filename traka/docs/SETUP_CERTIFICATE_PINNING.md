# Setup Certificate Pinning (Tahap 6)

Certificate pinning memastikan koneksi HTTP ke Traka API hanya ke server dengan sertifikat yang terdaftar, mencegah man-in-the-middle attack.

## Kapan Digunakan

- Hanya untuk **Traka Backend API** (bukan Google Maps, Firebase)
- Aktif saat `TRAKA_USE_HYBRID=true` dan `TRAKA_API_BASE_URL` terisi
- Opsional: jika `TRAKA_API_CERT_SHA256` kosong, pinning tidak aktif

## Cara Mendapatkan SHA-256 Fingerprint

### Dari domain yang sudah live

```bash
echo | openssl s_client -servername YOUR_API_DOMAIN -connect YOUR_API_DOMAIN:443 2>/dev/null | openssl x509 -noout -fingerprint -sha256
```

Contoh output:
```
SHA256 Fingerprint=AA:BB:CC:DD:EE:FF:...
```

Salin nilai setelah `=` (format dengan colon).

### Dari file sertifikat

```bash
openssl x509 -noout -fingerprint -sha256 -inform pem -in certificate.crt
```

## Konfigurasi Build

Tambahkan saat build Flutter:

```bash
flutter build apk --dart-define=TRAKA_API_BASE_URL=https://your-api.railway.app \
  --dart-define=TRAKA_USE_HYBRID=true \
  --dart-define=TRAKA_API_CERT_SHA256="AA:BB:CC:DD:EE:FF:..."
```

Atau di `codemagic.yaml` / CI:

```yaml
environment:
  dart_defines:
    TRAKA_API_BASE_URL: "https://your-api.railway.app"
    TRAKA_USE_HYBRID: "true"
    TRAKA_API_CERT_SHA256: "AA:BB:CC:DD:EE:FF:..."
```

## Rotasi Sertifikat

Saat API memperbarui sertifikat SSL:

1. Dapatkan fingerprint sertifikat baru
2. Update `TRAKA_API_CERT_SHA256` di build
3. Deploy versi baru app
4. User harus update app agar koneksi berfungsi lagi

**Tip**: Pin beberapa fingerprint (sertifikat lama + baru) saat masa transisi agar tidak ada downtime.

## Nonaktifkan Pinning

Hapus atau kosongkan `TRAKA_API_CERT_SHA256` saat build. App akan menggunakan koneksi HTTPS standar tanpa pinning.
