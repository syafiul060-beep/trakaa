# Test App Check - Langkah Cek

**Status:** App Check AKTIF (`ENFORCE_APP_CHECK = true`)

---

## Sebelum Test

### 1. Deploy Functions (WAJIB)

```powershell
cd d:\Traka\traka
firebase deploy --only functions
```

Tunggu sampai selesai. Tanpa deploy, Functions masih pakai config lama.

### 2. Pastikan Debug Token Terdaftar

- Firebase Console → App Check → **Debug tokens**
- Token dari logcat harus ada di daftar
- Format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

---

## Urutan Test

### Step 1: Stop app sepenuhnya

Tutup app (force close). Jangan hot reload.

### Step 2: Jalankan app fresh

```powershell
cd d:\Traka\traka
.\scripts\run_hybrid.ps1
```

Pilih device Android (HP terhubung USB).

### Step 3: Tunggu 5 detik di splash

App akan delay 5 detik setelah App Check init (workaround). Jangan tap apa-apa.

### Step 4: Coba login

Masukkan email → minta OTP → masukkan kode → login.

---

## Jika Gagal

### Rollback cepat (nonaktifkan App Check)

1. Edit `traka/functions/index.js` baris 80:
   ```javascript
   const ENFORCE_APP_CHECK = false;
   ```

2. Deploy:
   ```powershell
   firebase deploy --only functions
   ```

3. Login akan jalan lagi.

### Cek log

Saat login gagal, lihat di terminal/Logcat:
- `App Check: token ready OK` = token berhasil
- `App Check getToken: ...` = error saat ambil token
- Error `unauthenticated` / `permission-denied` = token tidak diterima Functions

---

## Checklist

- [ ] `firebase deploy --only functions` sudah dijalankan
- [ ] Debug token terdaftar di Firebase Console
- [ ] App dijalankan fresh (bukan hot reload)
- [ ] Tunggu 5 detik di splash sebelum login
- [ ] HP terhubung USB, USB debugging aktif
