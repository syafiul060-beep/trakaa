# Setup DATABASE_URL (PostgreSQL) untuk traka-api

traka-api membutuhkan PostgreSQL untuk endpoint `/api/orders` dan `/api/users`. Proyek ini menggunakan **Supabase** (PostgreSQL gratis).

---

## Langkah 1: Buat Project Supabase

1. Buka [Supabase Dashboard](https://supabase.com/dashboard)
2. Klik **New Project**
3. Isi:
   - **Name:** traka (atau nama lain)
   - **Database Password:** buat password kuat, **simpan** (dibutuhkan nanti)
   - **Region:** pilih terdekat (mis. Singapore `ap-southeast-1`)
4. Klik **Create new project** (tunggu ~2 menit)

---

## Langkah 2: Ambil Connection String (PENTING: Copy dari Supabase!)

**Jangan tebak format!** Host bisa `aws-0-xxx` atau `aws-1-xxx` tergantung project. Harus copy dari dashboard.

1. Di Supabase Dashboard, klik tombol **Connect** (pojok kanan atas)
2. Pilih **Session pooler** atau **Transaction pooler**
3. Copy **persis** connection string yang muncul
4. Ganti `[YOUR-PASSWORD]` dengan password database
5. Tambah `?sslmode=require` di akhir jika belum ada

## Langkah 2b: Alternatif – dari Project Settings

**Penting:** Gunakan **Session pooler**, bukan Direct connection (Direct = IPv6 only, sering gagal).

1. Di Supabase Dashboard, buka **Project Settings** (ikon gear di kiri bawah)
2. Klik menu **Database**
3. Scroll ke **Connection string**
4. Klik tab **URI**
5. Di dropdown **Method**, pilih **Session pooler** (bukan Direct connection)
6. Klik ikon **copy** di samping connection string
7. Format yang muncul:
   ```
   postgresql://postgres.[project-ref]:[YOUR-PASSWORD]@aws-0-[region].pooler.supabase.com:6543/postgres
   ```
8. **Ganti `[YOUR-PASSWORD]`** dengan password database Anda
9. Tambahkan `?sslmode=require` di akhir:
   ```
   postgresql://postgres.xxx:password@aws-0-xxx.pooler.supabase.com:6543/postgres?sslmode=require
   ```
10. Jika password punya karakter khusus (`@`, `#`, `%`), encode: `@` → `%40`, `#` → `%23`

**Contoh hasil:**
```
postgresql://postgres.fgwhlwpyqljmkmgmvuuf:Syafiulumam.0408@aws-0-ap-southeast-1.pooler.supabase.com:6543/postgres?sslmode=require
```

---

## Langkah 3: Jalankan Schema

1. Di Supabase Dashboard, buka **SQL Editor**
2. Klik **New query**
3. Buka file `traka-api/scripts/schema.sql` di editor
4. Copy seluruh isi file
5. Paste ke SQL Editor Supabase
6. Klik **Run** (atau Ctrl+Enter)

Jika berhasil, tabel `users` dan `orders` akan dibuat.

---

## Langkah 4: Tambah ke .env

1. Buka `traka-api/.env`
2. Tambah atau uncomment baris:
   ```
   DATABASE_URL=postgresql://postgres.xxx:password@aws-0-ap-southeast-1.pooler.supabase.com:6543/postgres
   ```
3. Ganti dengan connection string Anda dari Langkah 2
4. Untuk **produksi**, set `PG_POOL_MAX=50` atau `100` — lihat `docs/SETUP_PG_POOL_PRODUCTION.md`

---

## Langkah 5: Restart API

```powershell
cd d:\Traka\traka-api
npm run dev
```

Jika berhasil, tidak ada lagi pesan "DATABASE_URL not set - PostgreSQL disabled".

---

## Verifikasi

1. Buka http://localhost:3001/health
2. Response harus ada `"pg": true` di `checks`:
   ```json
   {"ok":true,"status":"traka-api","checks":{"api":true,"redis":true,"pg":true}}
   ```

---

## Opsi Lain: PostgreSQL Lokal

Jika pakai PostgreSQL di komputer sendiri:

1. Install PostgreSQL (atau pakai Docker)
2. Buat database: `CREATE DATABASE traka;`
3. Jalankan `schema.sql` via psql atau pgAdmin
4. Di `.env`:
   ```
   DATABASE_URL=postgresql://postgres:password@localhost:5432/traka
   ```
   (ganti `postgres`/`password` dengan user & password PostgreSQL Anda)
