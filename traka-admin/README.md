# Traka Admin

Web admin panel untuk aplikasi Traka (Android/iOS). Berbasis React + Vite + Tailwind + Firebase.

## Setup

1. **Install dependency**
   ```bash
   npm install
   ```

2. **Konfigurasi Firebase**
   - Buka Firebase Console > Project Settings > Your apps
   - Tambah web app (jika belum)
   - Copy config ke `.env` (lihat `.env.example`)

3. **Set user sebagai admin**
   - Di Firestore, buka `users/{uid}`
   - Tambah field `role: "admin"` (atau edit jika sudah ada)

4. **Keamanan: jangan mengandalkan UI saja**
   - Panel admin memang mengecek `role === 'admin'` di klien untuk menyembunyikan menu, **tetapi** akses data sebenarnya harus dibatasi di **Firestore Security Rules** (dan Cloud Functions jika dipakai): user non-admin tidak boleh membaca/menulis koleksi sensitif meskipun membuka URL atau memodifikasi JS di browser.
   - Setelah deploy, uji dengan akun non-admin bahwa query ke `orders`, `users`, dll. ditolak aturan.

5. **Pastikan app_config ada**
   - Buat document `app_config/settings` dengan field `tarifPerKm: 70` (untuk halaman Settings)

## Menjalankan

```bash
npm run dev
```

Buka http://localhost:5173

## Build & Deploy

```bash
npm run deploy
```

Atau manual: `npm run build` lalu `firebase deploy --only hosting`.

**Panduan lengkap**: Lihat [docs/DEPLOY_WEB_ADMIN.md](docs/DEPLOY_WEB_ADMIN.md) – termasuk setup situs terpisah agar tidak menimpa hosting utama.

## Hybrid (driver_status dari API)

Jika Flutter memakai `TRAKA_USE_HYBRID=true`, tambahkan di `.env`:

```
VITE_TRAKA_API_BASE_URL=https://url-backend-anda
VITE_TRAKA_USE_HYBRID=true
```

Tanpa ini, halaman Drivers/Dashboard/Users akan baca driver_status dari Firestore (kosong saat hybrid aktif).

## Sesi admin (idle & keluar)

- **Idle 30 menit** tanpa aktivitas (klik, ketik, scroll, sentuh) → logout otomatis + pesan di halaman login.
- **Keluar** memakai dialog (bukan `confirm` bawaan browser) agar lebih ramah keyboard dan pembaca layar.

## Struktur

- `src/pages/` - Halaman (Dashboard, Orders, Users, dll)
- `src/components/` - Komponen reusable
- `src/config/` - Config (apiConfig untuk hybrid)
- `src/services/` - API client (trakaApi)
- `src/firebase.js` - Konfigurasi Firebase

## Dokumentasi

- `docs/PERBAIKAN_ADMIN_UI_2025-03.md` - Ringkasan perbaikan UI/sesi/API hybrid (Maret 2025)
- `RANCANGAN_ADMIN_TRAKA.md` - Rancangan lengkap
- `WIREFRAME_UI.md` - Wireframe UI
