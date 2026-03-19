# Cegah API Key Terekspos ke Git

**Penting:** Jangan pernah commit API key asli ke repository. GitHub Secret Scanning akan mendeteksi dan mengirim alert.

---

## File yang JANGAN Di-commit (sudah di .gitignore)

| File | Isi |
|------|-----|
| `traka/lib/firebase_options.dart` | Firebase keys (generate via `flutterfire configure`) |
| `traka/android/key.properties` | MAPS_API_KEY |
| `traka/android/app/google-services.json` | Firebase Android config |
| `traka/ios/Runner/GoogleService-Info.plist` | Firebase iOS config |
| `traka/ios/Runner/Keys.plist` | MAPS_API_KEY untuk Maps iOS |
| `traka/hosting/firebase-config.js` | Firebase Web key |
| `traka/web/firebase-config.js` | Firebase Web key (track.html) |
| `traka-admin/.env` | VITE_FIREBASE_API_KEY, dll |
| `traka-admin/public/firebase-config.js` | Firebase Web key |

---

## Dokumen: JANGAN Tulis Key Asli

File seperti `API_KEY_REFERENSI.md`, `CEK_APLIKASI_API_KEY_APP_CHECK.md` — gunakan placeholder (`xxx`, `YOUR_KEY`) saja, bukan nilai asli.

---

## Jika Key Sudah Terekspos

1. **Rotate segera** — regenerate semua key di Google Cloud Console
2. **Update aplikasi** — ikuti `docs/ROTATE_API_KEYS_LANGKAH.md`
3. **Nonaktifkan key lama** — di Google Cloud Console → Credentials

> **Catatan:** Key yang sudah di-push ke Git history tetap bisa dilihat. Rotasi wajib.
