# Cara Menambah Akun Admin Web Traka

Jika akun admin terhapus di Firebase, ikuti langkah berikut untuk membuat akun admin baru.

---

## Langkah 1: Buat User di Firebase Authentication

1. Buka **Firebase Console** → project Anda (misalnya `syafiul-traka`)
2. Masuk ke **Authentication** → **Users**
3. Klik **Add user**
4. Isi:
   - **Email**: email admin (contoh: `admin@traka.id`)
   - **Password**: password minimal 6 karakter
5. Klik **Add user**
6. **Catat UID** user yang baru dibuat (klik user di daftar → copy User UID)

---

## Langkah 2: Buat Dokumen di Firestore

1. Masuk ke **Firestore Database**
2. Buka collection **`users`**
3. Klik **Add document**
4. **Document ID**: paste **UID** dari langkah 1 (harus sama persis dengan UID di Authentication)
5. Tambah field:
   - `role` (string): `admin`
   - `displayName` (string): nama admin (opsional)
   - `email` (string): email yang sama dengan di Auth (opsional)

6. Klik **Save**

---

## Contoh struktur dokumen Firestore

| Field        | Type   | Value              |
|-------------|--------|--------------------|
| role        | string | admin              |
| displayName | string | Admin Traka        |
| email       | string | admin@traka.id     |

---

## Langkah 3: Login ke Web Admin

1. Buka URL login admin: **https://traka-admin.web.app/pd-x7k** atau **https://syafiul-traka.web.app/admin/pd-x7k**
2. Masukkan email dan password yang dibuat di langkah 1
3. Klik **Login**

---

## Catatan

- **UID** di Firestore **harus sama** dengan UID di Firebase Authentication. Jika berbeda, login akan berhasil tapi akses admin ditolak ("Anda bukan admin").
- Pastikan domain admin sudah ada di **Authentication** → **Settings** → **Authorized domains** (traka-admin.web.app, syafiul-traka.web.app).
- Simpan email dan password admin di tempat aman.
