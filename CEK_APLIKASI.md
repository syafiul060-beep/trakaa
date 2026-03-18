# Laporan Pengecekan Aplikasi Traka

**Tanggal:** 17 Februari 2025

---

## 1. Ringkasan Kondisi

| Aspek | Status | Keterangan |
|-------|--------|------------|
| **Flutter App (traka)** | ✅ Baik | Versi 1.0.0+1, SDK ^3.10.7 |
| **Admin Web (traka-admin)** | ✅ Baik | React + Vite + Firebase |
| **Firestore Rules** | ✅ Diperbaiki | Admin bisa edit user |
| **Keamanan** | ✅ | Fake GPS aktif, kontribusi driver aktif |
| **Linter** | ✅ Bersih | Unused import sudah dihapus |

---

## 2. Firestore Rules – Masalah yang Ditemukan

### 2.1 Admin tidak bisa edit user

**File:** `traka/firestore.rules` (baris 7–9)

```javascript
match /users/{userId} {
  allow read: if true;
  allow write: if request.auth != null && request.auth.uid == userId;
}
```

**Masalah:** Admin web perlu mengedit user lain (displayName, phoneNumber, verified), tapi rules hanya mengizinkan write jika `request.auth.uid == userId`. Admin punya UID sendiri, jadi tidak bisa menulis ke dokumen user lain.

**Dampak:** Fitur "Edit User" di halaman Users admin akan gagal dengan error permission.

**Solusi:** Tambah kondisi untuk admin, misalnya:

```javascript
allow write: if request.auth != null
  && (request.auth.uid == userId
      || (exists(/databases/$(database)/documents/users/$(request.auth.uid))
          && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin'));
```

### 2.2 app_config – sudah benar

Rules saat ini:

```javascript
allow read: if request.auth != null;
allow write: if request.auth != null
  && exists(...) && get(...).data.role == 'admin';
```

- App mobile (penumpang/driver) bisa **baca** tarif, biaya pelanggaran, dll.
- Hanya admin yang bisa **tulis** (Settings).

---

## 3. Fitur yang Sudah Berjalan

- **Lacak Barang:** Bayar via Google Play, peta full-screen, notifikasi 5km/1km/500m
- **Lacak Driver:** Bayar via config, peta
- **Pelanggaran:** Model, service, ViolationPayScreen, admin Violations
- **Admin Web:** Dashboard, Orders, Users, Settings, Violations, Chat
- **Pencarian:** Dashboard, Orders, Users
- **Detail User:** Foto, lokasi terakhir, icon lacak (Google Maps)

---

## 4. Perbaikan Minor

### 4.1 Unused import

**File:** `traka/lib/screens/cek_lokasi_barang_screen.dart`

Import `lacak_barang_service.dart` tidak dipakai di file ini. Bisa dihapus untuk membersihkan kode.

---

## 5. URL Legal untuk Google Play

Setelah deploy traka-admin, halaman berikut tersedia:
- **Kebijakan Privasi:** `https://syafiul-traka.web.app/legal/privacy.html`
- **Syarat dan Ketentuan:** `https://syafiul-traka.web.app/legal/terms.html`

File ada di `traka-admin/public/legal/`. Isi URL Privacy Policy di Play Console → App content → Privacy policy.

---

## 6. Rekomendasi

1. ~~**Update Firestore rules**~~ ✅ Sudah diperbaiki – admin sekarang bisa edit user.
2. ~~**Hapus unused import**~~ ✅ Sudah dihapus di `cek_lokasi_barang_screen.dart`.
3. ~~**Privacy Policy URL**~~ ✅ Sudah dibuat – `traka-admin/public/privacy.html` dan `terms.html`.
4. **Sinkronkan** `traka/docs/FIRESTORE_RULES_LENGKAP.txt` dengan `traka/firestore.rules` agar dokumentasi sesuai implementasi.
5. **Pastikan** user admin punya `role: 'admin'` di Firestore `users/{uid}`.
6. **Pastikan** file `.env` di traka-admin sudah diisi dengan config Firebase.

---

## 7. Perintah Berguna

```bash
# Jalankan admin lokal
cd traka-admin && npm run dev

# Deploy admin
cd traka-admin && npm run deploy

# Deploy Firestore rules (setelah edit)
firebase deploy --only firestore:rules
```
