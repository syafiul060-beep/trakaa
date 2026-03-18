# Cara Menjalankan Traka Admin

Web admin Traka menggunakan **React + Vite** dan **Firebase (Firestore, Auth)**. Bisa dijalankan lokal atau di-deploy agar bisa diakses dari mana saja.

---

## 1. Persiapan (sekali saja)

### A. Install Node.js
- Download dari [nodejs.org](https://nodejs.org) (versi LTS)
- Pastikan `node` dan `npm` terinstall: buka terminal, ketik `node -v` dan `npm -v`

### B. Install Firebase CLI (untuk deploy)
```bash
npm install -g firebase-tools
```
Lalu login:
```bash
firebase login
```

### C. Setup Firebase config
1. Buat file `.env` di folder `traka-admin` (salin dari `.env.example`)
2. Isi dengan config Firebase Web dari **Firebase Console**:
   - Buka [Firebase Console](https://console.firebase.google.com) → project **syafiul-traka**
   - Project Settings (ikon gear) → General → scroll ke "Your apps"
   - Pilih Web app (atau tambah jika belum) → copy config

Contoh isi `.env` (untuk project syafiul-traka, bisa salin dari Firebase Console atau `traka/lib/firebase_options.dart` bagian web):
```
VITE_FIREBASE_API_KEY=AIzaSy...
VITE_FIREBASE_AUTH_DOMAIN=syafiul-traka.firebaseapp.com
VITE_FIREBASE_PROJECT_ID=syafiul-traka
VITE_FIREBASE_STORAGE_BUCKET=syafiul-traka.firebasestorage.app
VITE_FIREBASE_MESSAGING_SENDER_ID=652861002574
VITE_FIREBASE_APP_ID=1:652861002574:web:4bdc74993fc9859650041f
```

### D. Install dependency
```bash
cd traka-admin
npm install
```

---

## 2. Jalankan Lokal (untuk development)

```bash
cd traka-admin
npm run dev
```

Buka browser ke **http://localhost:5173**

- Login dengan akun yang punya `role: 'admin'` di Firestore `users/{uid}`
- Hanya bisa diakses dari komputer yang menjalankan perintah ini

---

## 3. Deploy ke Firebase Hosting (akses dari mana saja)

Setelah deploy, admin bisa diakses dari URL publik (misal: `https://syafiul-traka.web.app` atau custom domain).

### Langkah deploy:

```bash
cd traka-admin

# Satu perintah (build + deploy):
npm run deploy
```

Atau manual:
```bash
npm run build
firebase deploy --only hosting
```

- Pastikan sudah `firebase login` dan project `syafiul-traka` terpilih
- File hasil build ada di folder `dist/`
- Firebase Hosting akan serve dari folder `dist/` (sudah dikonfigurasi di `firebase.json`)

### URL setelah deploy
- Default: `https://syafiul-traka.web.app` (atau `https://syafiul-traka.firebaseapp.com`)
- Bisa tambah custom domain di Firebase Console → Hosting → Add custom domain

### Halaman Legal (untuk Google Play)
Setelah deploy, halaman berikut tersedia dan bisa dipakai sebagai URL di Play Console:
- **Kebijakan Privasi:** `https://syafiul-traka.web.app/legal/privacy.html`
- **Syarat dan Ketentuan:** `https://syafiul-traka.web.app/legal/terms.html`

File ada di `traka-admin/public/legal/` dan otomatis disalin ke `dist/legal/` saat build (Vite).

---

## 4. Ringkasan perintah

| Tujuan | Perintah |
|--------|----------|
| Jalankan lokal | `cd traka-admin` lalu `npm run dev` |
| Build (sebelum deploy) | `npm run build` |
| Deploy ke internet | `npm run build` lalu `firebase deploy --only hosting` |
| Preview build lokal | `npm run preview` |

---

## 5. Troubleshooting

**"Toko aplikasi tidak tersedia" / Firebase error**
- Pastikan `.env` sudah diisi dengan config yang benar
- Restart dev server setelah ubah `.env`

**Tidak bisa login**
- Pastikan user punya `role: 'admin'` di Firestore `users/{uid}`

**Deploy gagal**
- Pastikan `firebase login` sudah berhasil
- Cek project: `firebase use` (harus syafiul-traka)
- Pastikan `npm run build` berhasil tanpa error
