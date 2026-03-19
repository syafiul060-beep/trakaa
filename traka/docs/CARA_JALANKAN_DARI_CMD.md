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

---

## Run ke HP (USB)

```cmd
cd D:\Traka\traka
.\scripts\run_hybrid.bat
```

HP terhubung USB, USB debugging aktif. Pilih device HP saat diminta.

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

## Troubleshooting: Penumpang tidak menemukan driver

1. Pastikan driver sudah **Siap Kerja** dengan rute aktif (asal–tujuan terisi).
2. Driver dan penumpang pakai **mode yang sama** (keduanya hybrid atau keduanya non-hybrid).
3. Cek koneksi internet di kedua HP.
4. Coba **Driver sekitar** dulu (tanpa isi tujuan) — jika driver muncul, masalah di filter rute.
