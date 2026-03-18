# Pembebasan Lacak & Izin Fake GPS

Admin bisa mengatur daftar pengguna khusus tanpa ubah program. Dua fitur:

---

## 1. Penumpang Bebas Lacak Driver & Barang

**Firestore**: `app_config/lacak_exempt_users`  
**Field**: `userUids: ["uid1", "uid2", ...]`

User dalam daftar ini **tidak perlu bayar** Lacak Driver dan Lacak Barang. Berlaku untuk:
- Penumpang (travel)
- Pengirim (kirim barang)
- Penerima (kirim barang)

**Cara**: Admin Settings → Penumpang Bebas Lacak Driver & Barang → Tambah UID atau email → Simpan.

---

## 2. Pengguna Diizinkan Fake GPS

**Firestore**: `app_config/fake_gps_allowed_users`  
**Field**: `userUids: ["uid1", "uid2", ...]`

User dalam daftar ini **boleh pakai fake GPS/lokasi palsu** tanpa diblokir. Untuk:
- Testing / demo
- Pengguna yang diizinkan khusus (mis. tim internal)

**Cara**: Admin Settings → Pengguna Diizinkan Fake GPS → Tambah UID atau email → Simpan.

**Catatan**: Deteksi fake GPS aktif jika `kDisableFakeGpsCheck = false` di `location_service.dart`. Saat ini flag masih `true` (deteksi dimatikan). Untuk production, set `false` dan gunakan whitelist ini untuk user yang diizinkan.

---

## Ringkasan

| Daftar | Firestore | Fungsi |
|--------|-----------|--------|
| Driver Bebas Kontribusi | `contribution_exempt_drivers` (driverUids) | Driver tidak bayar iuran kontribusi |
| Penumpang Bebas Lacak | `lacak_exempt_users` (userUids) | Tidak bayar Lacak Driver & Barang |
| Fake GPS Allowed | `fake_gps_allowed_users` (userUids) | Boleh pakai lokasi palsu |
