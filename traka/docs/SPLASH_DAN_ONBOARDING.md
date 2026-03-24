# Splash & onboarding — catatan produk

## Alur saat ini

1. **`SplashScreen`** — animasi logo + teks TRAKA (±1,5 s), indikator loading; bisa **Lewati / Skip** untuk mempercepat animasi saja (navigasi tetap menunggu cek auth/update di wrapper).
2. **`SplashScreenWrapper`** — setelah frame pertama, cek update wajib, maintenance, auth, izin, lalu navigasi.
3. **`OnboardingScreen`** — setelah login pertama (preferensi `traka_onboarding_seen`), 3 halaman PageView.

## Saran pengembangan (opsional)

| Ide | Manfaat |
|-----|---------|
| **Branding konsisten** | Warna aksen splash selaras `Theme.of(context).colorScheme.primary` (bukan hanya hitam) agar selaras dark/light. |
| **Satu ilustrasi ringan** | SVG/PNG ringan di splash (bukan video) agar cold start tetap cepat. |
| **Onboarding: animasi halaman** | `AnimatedSwitcher` atau transisi `PageView` halus; hindari Lottie berat di cold start. |
| **Prefers reduced motion** | Splash menghormati **Pengurangan animasi** di pengaturan sistem (sudah didukung di kode). |
| **Jangan memblokir startup** | Tetap hindari `await` berat di `main()` sebelum `runApp` (sudah diarahkan ke init async). |

## File terkait

- `lib/screens/splash_screen.dart`
- `lib/screens/splash_screen_wrapper.dart`
- `lib/screens/onboarding_screen.dart`
