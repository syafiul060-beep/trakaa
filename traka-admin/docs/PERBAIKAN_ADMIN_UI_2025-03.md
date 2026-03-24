# Perbaikan UI admin Traka (Maret 2025)

Ringkasan perubahan pada **traka-admin** (React + Vite + Tailwind + Firebase), selaras dengan [`PERBAIKAN_UI_UX_PERFORMA_2025-03.md`](../../traka/docs/PERBAIKAN_UI_UX_PERFORMA_2025-03.md) di app mobile.

---

## 1. Navigasi & sesi

| Sebelum | Sesudah |
|---------|---------|
| Menu campur EN + emoji | Label **Bahasa Indonesia** + ikon **SVG** (`AdminNavIcons.jsx`) |
| `confirm()` logout | **Dialog** dengan `useFocusTrap`, Escape, backdrop |
| Tanpa idle timeout | **Auto logout 30 menit** idle → pesan di halaman login (`sessionStorage`) |

## 2. Login

- Pesan sesi habis (idle), `autoComplete` email/password, `aria-live` untuk error/info, tombol **Masuk**.

## 3. API hybrid (`trakaApi.js`)

- `getDriverStatusList` / `getDriverStatus` mengembalikan `{ status, drivers|driver, httpStatus? }`.
- **Dashboard** & **Drivers**: banner peringatan jika API error/jaringan + tombol **Coba lagi** (Drivers).

## 4. Label halaman (batch Indonesia)

- **Pesanan**: status internal → teks Indonesia (mis. *Menunggu kesepakatan*, *Disepakati*).
- **Detail pesanan**: status sama; *Info* → **Ringkasan**.
- **Pengguna**: kolom *Role* → **Peran**, *Verified* → **Terverifikasi**; placeholder & tab penghapusan.
- **Pelanggaran**: header tabel *User* / *Order* → **Pengguna** / **Pesanan**.
- **Log audit**: judul aksi audit full ID; judul halaman **Log audit**.
- **Siaran**: judul **Siaran notifikasi**; pesan error tidak memakai *Unknown error* mentah.
- **Laporan**: istilah *Fee* → **biaya** di ringkasan & grafik (konsisten ID).
- **Dasbor**: kartu *Pesanan Pending* → **Pesanan menunggu**.
- **Pengaturan**: *Maintenance Mode* → **Mode pemeliharaan**; *Lacak Barang – Fee per Order* → **biaya per pesanan**; teks *User* pada pesan daftar → **Pengguna**.
- **Percakapan (Chat)**: hitung *chat* → **percakapan**; fallback nama → **Pengguna**.

## 5. Keamanan (dokumentasi)

- **README**: admin UI bukan satu-satunya gate; wajib **Firestore Security Rules** + uji akun non-admin.

---

## File utama

- `src/components/Layout.jsx`, `AdminNavIcons.jsx`
- `src/pages/Login.jsx`
- `src/services/trakaApi.js`
- `src/pages/Dashboard.jsx`, `Drivers.jsx`, `Users.jsx`
- `src/pages/Orders.jsx`, `OrderDetail.jsx`, `Violations.jsx`, `AuditLog.jsx`, `Broadcast.jsx`, `Reports.jsx`
- `README.md`

---

## Yang tidak diubah di batch ini

- **Chat**: `confirm()` untuk akhiri percakapan (bisa dinaikkan ke modal seperti logout).
- **Pengaturan**: judul kartu lain (versi app, tarif, kontak) sudah ID; istilah teknis *app*, *UID* tetap.

## Rilis

Setelah merge: `npm run build`, lalu deploy hosting; jalankan smoke test login → dasbor → pesanan → pengaturan.
