# Perubahan iOS Bundle ID ke id.traka.app

Bundle ID iOS telah diselaraskan dengan Android (`id.traka.app`).

## File yang Diubah

- `ios/Runner.xcodeproj/project.pbxproj` — PRODUCT_BUNDLE_IDENTIFIER
- `lib/firebase_options.dart` — iosBundleId
- `codemagic.yaml` — bundle_identifier

## Langkah Setelah Perubahan

1. **Firebase Console:** Tambah aplikasi iOS baru dengan bundle ID `id.traka.app` (jika belum ada).
2. **Unduh** `GoogleService-Info.plist` baru untuk iOS app `id.traka.app`.
3. **Ganti** file di `ios/Runner/GoogleService-Info.plist`.
4. **Jalankan** `flutterfire configure` untuk memperbarui `firebase_options.dart` jika diperlukan.
5. **App Store Connect:** Jika app sudah dipublish dengan `com.example.traka`, buat app baru dengan bundle ID `id.traka.app` (tidak bisa mengubah bundle ID app yang sudah ada).

## Catatan

- Jika app iOS belum pernah dipublish, perubahan ini aman.
- Jika app sudah dipublish dengan `com.example.traka`, pertahankan bundle ID lama atau buat app baru di App Store Connect.
