# Profil performa peta driver (Flutter + Google Maps)

Panduan memeriksa **jank**, **frame time**, dan **beban rebuild** pada layar beranda driver — bisa dibandingkan subjektif dengan aplikasi Google Maps di perangkat yang sama.

## 1. Mode profile (wajib untuk angka yang masuk akal)

Debug mode **tidak** mewakili performa rilis.

Jika biasanya pakai **hybrid** (`dart-define` API + opsional Map WS), gunakan skrip yang sama dengan **`-Profile`**:

```powershell
cd traka
.\scripts\run_hybrid.bat -Profile -EnableMapWs -RealtimeWsUrl "https://<worker-realtime>.up.railway.app"
```

Atau tanpa WebSocket:

```powershell
.\scripts\run_hybrid.bat -Profile
```

Setara manual:

```powershell
cd traka
flutter run --profile
```

Atau build APK profile:

```powershell
flutter build apk --profile
```

Lalu pasang APK dan hubungkan `flutter attach --profile`.

## 2. Flutter DevTools — Performance

1. Saat `flutter run --profile` jalan, tekan **`p`** di terminal atau buka URL DevTools yang ditampilkan.
2. Buka tab **Performance** (atau **CPU Profiler** di versi lama).
3. **Record** → pindah ke tab **Beranda** driver → geser peta, zoom, mulai navigasi, diam beberapa detik → **Stop**.
4. Periksa:
   - **Frame chart**: batang di bawah **16 ms** (60 Hz) atau **8 ms** (120 Hz) = mulus.
   - **Jank** / frame merah: klik frame untuk melihat **timeline** — sering dari `build`, `layout`, atau platform view (peta).

## 3. Timeline — Widget rebuild

Di Performance, perhatikan apakah **`build`** untuk `DriverScreen` atau ancestor dipanggil terlalu sering saat GPS tick. Idealnya peta tidak memicu **seluruh** layar rebuild setiap detik; yang bergerak cukup marker/camera.

## 4. Repaint boundaries (visual)

Hanya **debug**:

```dart
// Contoh: sudah ada RepaintBoundary di sekitar beberapa overlay di driver_screen.
```

Di DevTools **Flutter inspector** → menu **⋮** → **Show Repaint Rainbow** — area yang berkedip terus = repaint berlebihan.

## 5. Firebase Performance (produksi / beta)

Trace otomatis **`driver_map_ready`**: dari `onMapCreated` sampai setelah **satu frame** pertama. Angka muncul di **Firebase Console → Performance** (setelah build dengan Firebase dikonfigurasi dan pengumpulan data aktif).

Bandingkan median **`driver_map_ready`** vs **`passenger_map_ready`** untuk melihat apakah layar driver lebih berat saat pertama buka peta.

## 6. Perbandingan dengan Google Maps

- **GM native**: tidak ada layer Flutter — biasanya frame platform view lebih “murah” untuk skenario navigasi murni.
- **Traka**: Flutter + `google_maps_flutter` + overlay Anda. Yang adil: bandingkan **skenario sama** (mis. hanya peta + geser, tanpa chat/Firestore berat di latar) dan **perangkat sama**, mode **profile**.

## 7. Jika frame sering merah

- Kurangi **`setState`** besar saat timer lokasi; isolasi perubahan ke subtree kecil.
- Hindari **`animateCamera`** bertumpuk (throttle sudah di `CameraFollowEngine`).
- Pertahankan **`RepaintBoundary`** di widget overlay yang jarang berubah.
- Periksa ukuran **marker bitmap** (decode ikon besar memakan UI thread).

## Perintah cepat (PowerShell)

```powershell
cd d:\Traka\traka
flutter run --profile -d <device_id>
```

`flutter devices` untuk melihat `device_id`.
