# Deploy Web Admin Traka

Panduan deploy traka-admin ke Firebase Hosting. Admin tersedia di **https://syafiul-traka.web.app/admin** (subpath dari situs utama).

---

## Prasyarat

1. **Firebase project sama dengan app** – traka-admin memakai project `syafiul-traka` (lihat `.firebaserc`)
2. **Firebase CLI** terpasang: `npm install -g firebase-tools`
3. **Login Firebase**: `firebase login`

---

## Langkah Deploy

Ada 2 URL admin:
- **traka-admin.web.app** – situs standalone (base `/`)
- **syafiul-traka.web.app/admin** – subpath dari situs utama (base `/admin/`)

### 1. Deploy ke traka-admin.web.app (standalone)

```powershell
cd d:\Traka\traka-admin
npm run build
firebase deploy --only hosting
```

### 2. Deploy ke syafiul-traka.web.app/admin

```powershell
cd d:\Traka\traka-admin
npm run build:syafiul

# Salin ke traka hosting
Remove-Item d:\Traka\traka\hosting\admin -Recurse -Force -ErrorAction SilentlyContinue
New-Item d:\Traka\traka\hosting\admin -ItemType Directory -Force
Copy-Item d:\Traka\traka-admin\dist\index.html d:\Traka\traka\hosting\admin\
Copy-Item d:\Traka\traka-admin\dist\assets d:\Traka\traka\hosting\admin\assets -Recurse -Force

# Deploy
cd d:\Traka\traka
firebase deploy --only hosting
```

### 2. Konfigurasi .env (di traka-admin)

Buat file `.env` di folder `traka-admin/` (copy dari `.env.example`):

```env
VITE_FIREBASE_API_KEY=xxx
VITE_FIREBASE_AUTH_DOMAIN=syafiul-traka.firebaseapp.com
VITE_FIREBASE_PROJECT_ID=syafiul-traka
VITE_FIREBASE_STORAGE_BUCKET=syafiul-traka.appspot.com
VITE_FIREBASE_MESSAGING_SENDER_ID=652861002574
VITE_FIREBASE_APP_ID=xxx
```

**Sumber nilai**: Firebase Console → Project Settings → Your apps → Web app.

Jika pakai **hybrid mode** (driver_status dari API):

```env
VITE_TRAKA_API_BASE_URL=https://trakaa-production.up.railway.app
VITE_TRAKA_USE_HYBRID=true
```

(Samakan dengan `PRODUCTION_API_BASE_URL.txt` di root monorepo jika URL Railway Anda berbeda.)

### 3. URL Hasil Deploy

Setelah deploy, admin tersedia di:

- **https://traka-admin.web.app** (standalone)
- **https://syafiul-traka.web.app/admin**
- Login: **https://traka-admin.web.app/pd-x7k** atau **https://syafiul-traka.web.app/admin/pd-x7k**

---

## Authorized Domains (Firebase Auth)

Agar login berfungsi di kedua URL:

1. Firebase Console → **Authentication** → **Settings** → **Authorized domains**
2. Pastikan **`syafiul-traka.web.app`** dan **`traka-admin.web.app`** sudah ada

---

## Custom Domain (Opsional)

Untuk URL seperti `admin.traka.id`:

1. Firebase Console → **Hosting** → **Add custom domain**
2. Ikuti langkah verifikasi DNS
3. Setelah aktif, update **Authorized domains** di Auth

---

## Cek Setelah Deploy

- [ ] Buka URL admin di browser
- [ ] Login dengan user yang punya `role: "admin"` di Firestore
- [ ] Cek Dashboard, Orders, Settings
- [ ] Jika hybrid: cek halaman Drivers menampilkan data dari API

---

## Troubleshooting

| Masalah | Solusi |
|---------|--------|
| Login gagal / redirect loop | Tambah domain ke Authorized domains di Firebase Auth |
| Halaman kosong / 404 | Pastikan `firebase.json` punya rewrite ke `/index.html` (sudah ada) |
| Drivers/Dashboard kosong | Jika hybrid: set `VITE_TRAKA_API_BASE_URL` dan `VITE_TRAKA_USE_HYBRID=true` di .env sebelum build |
| Broadcast gagal | Pastikan Cloud Functions sudah deploy (`firebase deploy --only functions`) dari folder `traka/` |
