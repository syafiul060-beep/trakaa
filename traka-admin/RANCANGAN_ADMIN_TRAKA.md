# Rancangan Web Admin Traka

## 1. Ringkasan

Web admin untuk mengelola aplikasi Traka (travel & kirim barang). Berbasis HTML, CSS, JavaScript, dapat diakses dari mana saja via browser.

---

## 2. Stack Teknologi

| Komponen | Pilihan | Alasan |
|----------|---------|--------|
| Framework | **React** atau **Vue.js** | Populer, banyak dokumentasi, komponen reusable |
| Styling | **Tailwind CSS** | Cepat, responsif, konsisten |
| Backend | **Firebase** (sama dengan app) | Data sudah ada, tidak perlu backend baru |
| Auth | **Firebase Auth** | Login admin, integrasi dengan users |
| Hosting | **Firebase Hosting** atau **Vercel** | Gratis, HTTPS, CDN global |
| Build | **Vite** | Build cepat, modern |

**Rekomendasi:** React + Tailwind + Firebase + Vite

---

## 3. Struktur Firestore (Referensi)

```
Firestore
├── users/                    # Pengguna (driver, penumpang)
│   └── {uid}
│       ├── displayName
│       ├── email
│       ├── phoneNumber
│       ├── photoUrl
│       ├── verified
│       ├── role              # 'admin' | 'driver' | 'penumpang'
│       ├── vehicleJumlahPenumpang
│       ├── totalPenumpangServed
│       └── contributionPaidUpToCount
│
├── orders/                   # Pesanan
│   └── {orderId}
│       ├── orderNumber
│       ├── passengerUid, driverUid
│       ├── status            # pending_agreement, agreed, picked_up, completed, cancelled
│       ├── orderType         # travel, kirim_barang
│       ├── originText, destText
│       ├── createdAt, completedAt
│       └── messages/         # Subcollection chat
│
├── driver_status/            # Status driver aktif
│   └── {driverUid}
│       ├── status            # siap_kerja, tidak_aktif
│       ├── latitude, longitude
│       └── routeOriginText, routeDestText
│
├── driver_schedules/         # Jadwal keberangkatan
│   └── {driverUid}
│       └── schedules[]       # Array jadwal
│
├── route_sessions/           # Riwayat sesi rute
├── completed_trips/          # Perjalanan selesai
├── app_config/
│   └── settings             # tarifPerKm, dll
├── vehicle_brands/           # Merek kendaraan
└── vehicle_data/             # Data kendaraan per driver
```

---

## 4. Struktur Halaman (Sitemap)

```
/admin
├── /login                    # Login admin
├── /                         # Dashboard (redirect ke /dashboard)
├── /dashboard                # Ringkasan statistik
├── /orders                   # Daftar pesanan
│   ├── /                    # List semua order
│   └── /:id                 # Detail order
├── /users                    # Manajemen pengguna
│   ├── /                    # List users (filter: driver/penumpang)
│   └── /:uid                # Detail user
├── /drivers                  # Driver aktif & jadwal
│   ├── /                    # List driver + status
│   └── /:uid/schedules      # Jadwal driver
├── /reports                  # Laporan
│   ├── /orders              # Laporan pesanan
│   └── /revenue             # Laporan pendapatan
├── /settings                 # Pengaturan aplikasi
│   ├── /tarif               # Tarif per km
│   └── /general             # Pengaturan umum
└── /logout                   # Logout
```

---

## 5. Rincian Halaman

### 5.1 Login (`/login`)
- Form: email + password
- Firebase Auth
- Cek `users/{uid}.role === 'admin'` sebelum akses
- Redirect ke `/dashboard` jika sukses
- Simpan token/session

### 5.2 Dashboard (`/dashboard`)
**Kartu statistik (hari ini / minggu ini / bulan ini):**
- Total pesanan (agreed, picked_up, completed)
- Pesanan dibatalkan
- Total driver aktif
- Total penumpang baru
- Grafik sederhana (Chart.js atau Recharts): trend pesanan 7 hari

**Tabel singkat:**
- 5 pesanan terbaru
- 5 driver aktif

### 5.3 Orders (`/orders`)
**Tabel dengan filter:**
- Status: Semua, Pending, Agreed, Picked Up, Completed, Cancelled
- Tipe: Semua, Travel, Kirim Barang
- Tanggal: range date picker
- Search: nomor pesanan, nama penumpang/driver

**Kolom:** No. Pesanan, Penumpang, Driver, Rute, Status, Tipe, Tanggal, Aksi

**Detail order (`/orders/:id`):**
- Info lengkap order
- Timeline status
- Link ke chat (jika perlu)
- Tombol: Lihat di map (opsional)

### 5.4 Users (`/users`)
**Tabel dengan filter:**
- Role: Semua, Driver, Penumpang, Admin
- Search: nama, email, telepon
- Verified: Ya/Tidak

**Kolom:** Foto, Nama, Email, Telepon, Role, Verified, Terdaftar, Aksi

**Detail user (`/users/:uid`):**
- Profil lengkap
- Riwayat pesanan user
- Tombol: Set sebagai admin, Verifikasi, Nonaktifkan (opsional)

### 5.5 Drivers (`/drivers`)
**Tabel:**
- Driver yang punya vehicle_data atau pernah jadi driver di orders
- Status: Aktif (siap_kerja) / Tidak aktif
- Lokasi saat ini (dari driver_status)
- Rute aktif
- Jumlah penumpang hari ini

**Detail:** Jadwal keberangkatan, riwayat rute

### 5.6 Reports (`/reports`)
**Laporan pesanan:**
- Export CSV/Excel: semua order dalam range tanggal
- Filter: status, tipe

**Laporan pendapatan:**
- Total tripFareRupiah (kontribusi aplikasi) per periode
- Per driver (opsional)

### 5.7 Settings (`/settings`)
**Tarif:**
- Edit `app_config/settings.tarifPerKm` (70–85)
- Simpan ke Firestore

**Umum:**
- Pengaturan lain dari app_config (jika ada)

---

## 6. Keamanan

### 6.1 Firestore Rules
Tambahkan rule untuk admin:

```javascript
// users: admin bisa baca semua, user biasa hanya baca sendiri
match /users/{userId} {
  allow read: if request.auth != null && 
    (request.auth.uid == userId || 
     get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin');
  allow write: if request.auth != null && 
    get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
}

// orders: admin bisa baca semua
match /orders/{orderId} {
  allow read: if request.auth != null && 
    (/* existing rules */ || 
     get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin');
}
```

### 6.2 Role Admin
- Tambah field `role: 'admin'` di document `users/{adminUid}`
- Bisa buat via Firebase Console atau script satu kali

---

## 7. Struktur Folder Project

```
traka-admin/
├── public/
│   └── index.html
├── src/
│   ├── main.jsx
│   ├── App.jsx
│   ├── firebase.js          # Config Firebase
│   ├── components/
│   │   ├── Layout.jsx       # Sidebar + header
│   │   ├── Sidebar.jsx
│   │   ├── DataTable.jsx    # Tabel reusable
│   │   └── StatCard.jsx
│   ├── pages/
│   │   ├── Login.jsx
│   │   ├── Dashboard.jsx
│   │   ├── Orders.jsx
│   │   ├── OrderDetail.jsx
│   │   ├── Users.jsx
│   │   ├── UserDetail.jsx
│   │   ├── Drivers.jsx
│   │   ├── Reports.jsx
│   │   └── Settings.jsx
│   ├── hooks/
│   │   └── useAuth.js
│   └── utils/
│       └── formatters.js
├── package.json
├── vite.config.js
├── tailwind.config.js
└── firebase.json             # Hosting config
```

---

## 8. UI/UX

### 8.1 Desain
- **Sidebar kiri:** Menu navigasi (Dashboard, Orders, Users, Drivers, Reports, Settings)
- **Header:** Judul halaman, nama admin, logout
- **Konten:** Area utama dengan padding
- **Warna:** Sesuaikan brand Traka (bisa orange/hijau dari app)

### 8.2 Responsif
- Desktop-first
- Tablet: sidebar collapse jadi icon
- Mobile: hamburger menu

### 8.3 Library UI (opsional)
- **DaisyUI** (Tailwind components) – cepat
- **Shadcn/ui** – modern, aksesibel
- **Ant Design** – lengkap untuk admin

---

## 9. Langkah Implementasi

### Fase 1 (MVP)
1. Setup project (Vite + React + Tailwind + Firebase)
2. Login admin
3. Dashboard (statistik dasar)
4. Halaman Orders (list + detail)
5. Deploy ke Firebase Hosting

### Fase 2
6. Halaman Users
7. Halaman Drivers
8. Settings (tarif)

### Fase 3
9. Reports & export
10. Perbaikan UI/UX
11. Custom domain

---

## 10. Checklist Sebelum Mulai

- [ ] Buat project Firebase terpisah untuk admin ATAU pakai project Traka yang sama
- [ ] Tambah web app di Firebase Console
- [ ] Copy config (apiKey, authDomain, dll) ke `.env`
- [ ] Tambah 1 user sebagai admin: set `users/{uid}.role = 'admin'`
- [ ] Update Firestore Rules untuk akses admin
- [ ] Siapkan domain (opsional): admin.traka.id

---

## 11. Referensi

- Firebase Web: https://firebase.google.com/docs/web/setup
- React: https://react.dev
- Vite: https://vitejs.dev
- Tailwind: https://tailwindcss.com
- Firebase Hosting: https://firebase.google.com/docs/hosting
