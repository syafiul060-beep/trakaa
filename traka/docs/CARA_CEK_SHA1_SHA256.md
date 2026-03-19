# Cara Cek SHA-1 & SHA-256 untuk Firebase / App Check

---

## Perbaikan Error dari Screenshot

### 1. `keytool` tidak dikenali
**Penyebab:** Java/JDK tidak ada di PATH.

**Solusi:** Pakai `gradlew signingReport` (tidak perlu keytool manual). Gradle punya Java sendiri.

---

### 2. `gradlew` tidak dikenali
**Penyebab:** Perintah dijalankan dari folder **salah**. `gradlew` ada di folder `android/`, bukan di root proyek.

**Benar:**
```powershell
cd d:\Traka\traka\android
.\gradlew.bat signingReport
```

**Salah:**
```powershell
cd d:\Traka\traka
.\gradlew signingReport   # ❌ gradlew tidak ada di sini
```

---

### 3. `scripts\run_hybrid.ps1` tidak ditemukan
**Penyebab:** Dijalankan dari folder `android/`, sedangkan `scripts` ada di folder **traka/** (parent).

**Benar:**
```powershell
cd d:\Traka\traka
.\scripts\run_hybrid.ps1
```

**Salah:**
```powershell
cd d:\Traka\traka\android
.\scripts\run_hybrid.ps1   # ❌ scripts ada di parent
```

---

### 4. Error "log reader stopped" saat flutter run
**Penyebab:** Masalah koneksi debug ke HP (Samsung SM-N970F). Bisa karena USB, driver, atau HP lock.

**Coba:**
- Cabut dan pasang lagi kabel USB
- Aktifkan **USB debugging** di HP
- Izinkan **USB debugging** saat muncul popup
- Coba kabel USB lain
- Restart HP dan PC

---

## SHA-1 & SHA-256 Anda (Debug)

Dari `gradlew signingReport`:

| | Nilai |
|---|-------|
| **SHA-1** | `89:B7:9A:71:C3:7C:52:E9:4C:8A:DC:56:B5:5F:A6:62:58:F0:BD:62` |
| **SHA-256** | `92:15:C2:2F:74:47:2F:1D:C1:D6:7F:0D:09:15:D9:CF:F8:C0:06:3B:99:0D:20:1D:0F:6E:23:16:88:69:1E:CE` |
| **Store** | `C:\Users\syafi\.android\debug.keystore` |

---

## Daftarkan di Firebase Console

1. Buka [Firebase Console](https://console.firebase.google.com/) → project **syafiul-traka**
2. **Project settings** (ikon roda gigi) → **Your apps**
3. Pilih app Android **id.traka.app**
4. Scroll ke **SHA certificate fingerprints**
5. Klik **Add fingerprint** → paste **SHA-1** di atas
6. Klik **Add fingerprint** lagi → paste **SHA-256** di atas

---

## Perintah Ringkas

```powershell
# Dapatkan SHA-1 & SHA-256
cd d:\Traka\traka\android
.\gradlew.bat signingReport

# Jalankan app (dari root proyek)
cd d:\Traka\traka
.\scripts\run_hybrid.ps1
```
