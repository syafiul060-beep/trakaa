# Troubleshooting: Gagal Memuat Rute (Directions API)

Error: **"Gagal memuat rute. Pastikan Directions API aktif di Google Cloud Console."**

Directions API sudah aktif, tapi rute tetap gagal? Cek hal berikut:

---

## 1. MAPS_API_KEY Tidak Terkirim ke App

**Penyebab paling sering:** App di HP tidak mendapat `MAPS_API_KEY`.

### Cek: Bagaimana app dijalankan di HP?

| Cara jalankan | MAPS_API_KEY terkirim? |
|---------------|------------------------|
| `.\scripts\run_hybrid.ps1` + HP terhubung USB | ✅ Ya (jika ada device dipilih) |
| APK di-install manual (build lama) | ❌ Mungkin kosong (tergantung build) |
| Dari Play Store / internal testing | ❌ Perlu build dengan `build_hybrid.ps1` |

### Solusi A: Jalankan via run_hybrid.ps1

```powershell
cd d:\Traka\traka
.\scripts\run_hybrid.ps1
```

- HP harus terhubung USB
- USB debugging aktif
- Pilih device HP saat Flutter tanya (atau gunakan `-Device <id>` jika ada banyak device)
- **WAJIB** muncul: `MAPS_API_KEY: AIzaSyBhWS...` (hijau) di terminal — jika tidak, key tidak terkirim

### Solusi B: Rebuild APK dengan key

Jika pakai APK yang di-install:

```powershell
cd d:\Traka\traka
.\scripts\build_hybrid.ps1
```

Lalu install APK baru ke HP. Pastikan muncul `MAPS_API_KEY: AIzaSyBhWS...` saat build.

---

## 2. API Key Restrictions (key maps)

Google Cloud Console → Credentials → **key maps** → Edit

### API restrictions
- Pilih **Restrict key**
- Pastikan **Directions API** ada di daftar
- Atau pilih **Don't restrict key** untuk uji coba

### Application restrictions (jika pakai)
- Jika **Android apps** dipilih: tambah `id.traka.app` + SHA-1 debug/release
- Jika salah SHA-1, request ditolak
- Untuk uji: pilih **None** sementara

---

## 3. Billing

Directions API memerlukan **billing aktif** di project GCP.

- Billing → pastikan project punya billing account
- Tanpa billing, request bisa ditolak meski API sudah enabled

---

## 4. Cek di Log (Debug)

Saat app jalan, lihat log Flutter/Logcat. Jika muncul:

```
Directions API: MAPS_API_KEY kosong. Jalankan via run_hybrid.ps1...
```

Berarti key tidak terkirim. Pastikan jalankan via `run_hybrid.ps1` atau rebuild dengan `build_hybrid.ps1`.

---

## Checklist Cepat

- [ ] Jalankan via `.\scripts\run_hybrid.ps1` (bukan `flutter run` biasa)
- [ ] HP terhubung USB, pilih device HP
- [ ] Muncul `MAPS_API_KEY: AIzaSyBhWS...` di terminal
- [ ] Key maps: Directions API di API restrictions (atau Don't restrict key)
- [ ] Billing aktif di project syafiul-traka
