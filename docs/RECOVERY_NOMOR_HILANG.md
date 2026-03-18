# Recovery Akun – Nomor Hilang / Tidak Aktif

Panduan untuk menangani user yang tidak bisa login karena nomor telepon hilang, tidak aktif, atau tidak bisa diakses.

---

## Pencegahan

- **Tambah Email** di profil: dorong user menambah email sebagai backup. Teks di profil sudah diupdate: *"Email opsional untuk notifikasi dan recovery jika nomor hilang."*
- User yang punya email bisa login dengan email + password dan ganti nomor di profil.

---

## Recovery via Kode (nomor hilang & belum punya email)

### Alur

1. User hubungi support (WhatsApp, email, dll.)
2. Support verifikasi identitas (KTP, selfie, nama, nomor lama)
3. Admin cari user di Firestore `users` (by phoneNumber atau displayName)
4. Admin jalankan script untuk generate kode recovery
5. Admin kirim kode ke user
6. User buka app → Login → "Nomor hilang? Masukkan kode recovery" → masukkan kode → Masuk
7. Setelah masuk, user bisa "Ubah No. Telepon" di profil

### Generate kode (admin)

**Opsi A: Script lokal (disarankan)**

```bash
cd d:\Traka\traka\functions
node scripts/create-recovery-token.js <uid>
```

- `uid`: Firebase Auth UID user (dari Firestore `users/{uid}`)
- Output: kode 8 karakter (contoh: `AB3XY7K2`)
- Kode berlaku 15 menit, one-time use

**Opsi B: Web Admin Traka**

1. Login ke web admin (traka-admin)
2. Buka **Users** → klik user untuk melihat detail
3. Klik tombol **Kode Recovery**
4. Konfirmasi (verifikasi identitas dulu)
5. Kode muncul → salin ke clipboard → kirim ke user via WhatsApp/email

**Opsi C: Cloud Function (script)**

Jika admin punya script yang memanggil Cloud Function:

1. Set env: Firebase Console → Functions → Environment variables → `RECOVERY_ADMIN_SECRET` = (rahasia)
2. Panggil `createRecoveryToken` dengan `{ adminSecret, uid }`
3. Response: `{ code, expiresInMinutes }`

Atau admin login web bisa memanggil tanpa adminSecret (cek role=admin dari Firestore).

---

## Keamanan

- Verifikasi identitas wajib sebelum generate kode
- Kode one-time use (dihapus setelah dipakai)
- Kode kedaluwarsa 15 menit
- Script lokal butuh `serviceAccountKey.json` (jangan commit ke repo)

---

## File terkait

| File | Fungsi |
|------|--------|
| `traka/lib/screens/login_screen.dart` | Link "Nomor hilang? Masukkan kode recovery", dialog, `consumeRecoveryCode` |
| `traka/lib/screens/profile_*_screen.dart` | Teks recovery di sheet No. Telepon & Email |
| `traka/functions/index.js` | `createRecoveryToken`, `consumeRecoveryCode` |
| `traka/functions/scripts/create-recovery-token.js` | Script admin generate kode |
