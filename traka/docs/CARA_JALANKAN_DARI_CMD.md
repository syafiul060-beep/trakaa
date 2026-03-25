# Cara Jalankan dari CMD (tanpa PowerShell)

Karena Execution Policy memblokir `.ps1`, pakai file **.bat** — bisa dijalankan dari **cmd** atau **PowerShell**.

---

## Mode Hybrid vs Non-Hybrid

**Penting:** Driver dan penumpang harus memakai mode yang sama agar penumpang bisa menemukan driver aktif.

| Mode | Perintah | Driver status |
|------|----------|---------------|
| **Hybrid** | `run_hybrid.bat` | API + Firestore |
| **Non-hybrid** | `flutter run` (tanpa hybrid) | Firestore saja |

- Jika driver pakai `run_hybrid.bat` dan penumpang pakai `flutter run` biasa → penumpang tetap bisa menemukan driver (dual-write + fallback).
- Jika penumpang pakai hybrid dan driver tidak → fallback ke Firestore.

**Estimasi chat (dev):** pesan terjadwal memakai geocode teks alamat; angka bisa menyimpang dari rute nyata. Lihat [`ALUR_PENUMPANG_DRIVER_PERBAIKAN.md`](ALUR_PENUMPANG_DRIVER_PERBAIKAN.md).

---

## Run ke HP (USB)

**Di HP:** aktifkan **Opsi pengembang** → **Debugging USB**. Kabel data (bukan charge saja). Saat pertama kali, HP minta **izin debugging** dari PC ini — setujui.

**Cek HP dikenali:**

```cmd
cd D:\Traka\traka
flutter devices
```

Kalau muncul `unauthorized`, cabut–pasang USB dan terima dialog di HP.

**Jalankan app (hybrid) langsung ke HP** — ini yang paling cepat untuk uji:

```cmd
cd D:\Traka\traka
.\scripts\run_hybrid.bat
```

Jika ada beberapa perangkat (Chrome, Windows, HP), pilih nomor HP saat diminta, **atau** pakai ID perangkat supaya tidak salah target:

```cmd
.\scripts\run_hybrid.bat -Device <device_id>
```

`<device_id>` = kolom kedua output `flutter devices` (bukan nama HP).

**Alternatif: build APK lalu pasang lewat USB** (tanpa `flutter run`, cocok untuk uji APK release):

```cmd
cd D:\Traka\traka
.\scripts\build_hybrid.bat -Target apk
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

`adb` ada di folder `platform-tools` Android SDK (atau sudah di PATH jika Android Studio terpasang).

### Hybrid + realtime peta (Tahap 4 — Socket.IO worker)

Sama seperti build Play Store: tambah flag worker (URL **HTTPS** service `traka-realtime-worker`, bukan API REST):

```cmd
.\scripts\run_hybrid.bat -EnableMapWs -RealtimeWsUrl "https://<worker-realtime>.up.railway.app"
```

Tanpa kedua argumen itu, app tetap pakai hybrid biasa; posisi driver di peta mengikuti stream/polling (fallback).

---

## Build untuk Play Store

**App Bundle (untuk upload Play Store):**
```cmd
cd D:\Traka\traka
.\scripts\build_hybrid.bat -Target appbundle
```

**APK (untuk testing):**
```cmd
.\scripts\build_hybrid.bat -Target apk
```

Output:
- App Bundle: `build/app/outputs/bundle/release/app-release.aab`
- APK: `build/app/outputs/flutter-apk/app-release.apk`

---

## Upload ke Play Store

1. Build: `.\scripts\build_hybrid.bat -Target appbundle`
2. Buka [Google Play Console](https://play.google.com/console)
3. Pilih app Traka → Production/Internal testing
4. Buat release baru → Upload file `app-release.aab`

---

## Ringkasan

| Tugas | Script | Perintah |
|-------|--------|----------|
| Run ke HP (hybrid) | `run_hybrid.bat` | `.\scripts\run_hybrid.bat` |
| Run ke HP (non-hybrid) | — | `flutter run` |
| **Build APK** (testing) | `build_hybrid.bat` | `.\scripts\build_hybrid.bat -Target apk` |
| **Build App Bundle** (Play Store) | `build_hybrid.bat` | `.\scripts\build_hybrid.bat -Target appbundle` |

**Catatan:** `run_hybrid.bat` untuk **jalankan** ke HP. `build_hybrid.bat` untuk **build** APK/AAB. Jangan pakai run_hybrid untuk build.

**Tidak perlu PowerShell** — cmd cukup. File .bat memanggil PowerShell dengan bypass otomatis.

---

## Troubleshooting: `Invalid file` / `aapt dump` / manifest APK gagal

Pesan seperti **Error opening archive … app-debug.apk: Invalid file**, **AndroidManifest.xml not found**, atau **No application found for TargetPlatform.android_arm64** biasanya berarti **APK di folder `build` rusak atau build terputus** (bukan karena Socket.IO atau URL worker).

1. Tutup proses yang bisa mengunci file: hentikan `flutter run` lama, tutup build Gradle yang hang, optional matikan sementara antivirus pada folder proyek.
2. Dari folder `traka/`:
   ```cmd
   flutter clean
   flutter pub get
   ```
3. Jalankan lagi `.\scripts\run_hybrid.bat` (dengan atau tanpa `-EnableMapWs`).
4. Jika masih error: pastikan `android\app\src\main\AndroidManifest.xml` ada (seharusnya sudah ada di repo), lalu `flutter doctor -v` untuk memastikan Android SDK / **build-tools** terpasang.

---

## Troubleshooting: Penumpang tidak menemukan driver

1. Pastikan driver sudah **Siap Kerja** dengan rute aktif (asal–tujuan terisi).
2. Driver dan penumpang pakai **mode yang sama** (keduanya hybrid atau keduanya non-hybrid).
3. Cek koneksi internet di kedua HP.
4. Coba **Driver sekitar** dulu (tanpa isi tujuan) — jika driver muncul, masalah di filter rute.

---

## Uji cepat: tap ikon driver di peta (penumpang)

Setelah `.\scripts\run_hybrid.bat` dan ada driver aktif di peta:

1. Tap ikon mobil driver → bottom sheet terbuka (ada handle + tombol tutup).
2. Driver **terdekat** (yang ikonnya disorot sebagai rekomendasi di peta) → di sheet muncul chip **Direkomendasikan**.
3. Baris ETA memuat rute ke lokasi Anda; saat memuat ada indikator loading, lalu teks perkiraan waktu. Jika gagal (koneksi/API), muncul pesan singkat dan **Coba lagi**.
4. **Kompas peta (opsional):** di samping kontrol satelit/zoom, ikon jelajah — ketuk untuk **ikut arah jalan** (heading-up), ketuk lagi untuk **utara ke atas**. Setelah zoom otomatis ke semua driver hasil cari, mode ikut arah dimatikan.
5. **Lalu lintas:** ikon lampu lalu lintas di kontrol kanan — default hijau/oranye (layer aktif); ketuk untuk mematikan jika peta terasa ramai.

Lihat juga [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md) untuk regresi alur utama.

**North-up vs ikut heading (Grab-sejenis):** [`MAPS_KAMERA_NORTH_UP_VS_HEADING.md`](MAPS_KAMERA_NORTH_UP_VS_HEADING.md).
