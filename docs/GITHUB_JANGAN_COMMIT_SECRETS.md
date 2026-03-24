# Sebelum `git push` ke GitHub — cek rahasia

## Jangan sampai ter-commit

- **API key** Google Maps, Directions, Places, dsb.
- **Firebase** `google-services.json` / `GoogleService-Info.plist` jika kebijakan tim melarang (banyak tim tetap commit file ini; pastikan **Firebase Console** dibatasi dengan SHA + package name + App Check).
- File **`firebase_options.dart`** / kunci service account JSON.
- **`.env`**, `REDIS_URL` dengan password, `JWT_SECRET`, `SENTRY_DSN` pribadi, token bot.
- Kunci **Play App Signing** / keystore upload.

## Perintah cepat (dari root repo)

```bash
# Pola umum kunci (sesuaikan jika terlalu banyak false positive)
git grep -n "AIza" || true
git grep -n "PRIVATE KEY" || true
git grep -n "REDIS_URL=rediss://" || true
```

## Sudah ada di `.gitignore`

- `traka/lib/firebase_options.dart` (lihat `traka/.gitignore`)
- `traka-api/.env`, `traka-api/firebase-service-account.json`
- Root: lihat `.gitignore` di root monorepo Traka

## Setelah repo baru di-init

1. Salin `.env.example` → `.env` lokal (jangan commit `.env`).
2. Gunakan **GitHub Secrets** / CI variables untuk deploy.
3. Tinjau **Files changed** di PR sebelum merge.

Dokumen terkait: `docs/CEGAH_API_KEY_TEREKSPOS.md` (jika ada di subproyek).
