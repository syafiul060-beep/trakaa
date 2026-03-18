# Tahap 4: Custom Icon Mobil (Grab/Uber/InDrive Style)

Panduan mengganti icon mobil dengan desain baru ala ride-sharing.

---

## Spesifikasi Desain

### Gaya Referensi
| Aplikasi | Karakteristik |
|----------|---------------|
| **Grab** | Mobil sederhana, top-down view, warna solid (hijau/merah) |
| **Uber** | Mobil minimalis, ikon datar, mudah dikenali |
| **InDrive** | Mobil compact, jelas dari zoom jauh |

### Persyaratan Teknis
- **View:** Top-down (dilihat dari atas), mobil menghadap ke bawah
- **Format:** PNG dengan transparansi (alpha channel)
- **Ukuran sumber:** 96×96 px atau 128×128 px (akan di-scale otomatis)
- **Warna:**
  - `car_merah.png`: Merah (#E53935 atau serupa) – driver diam
  - `car_hijau.png`: Hijau (#43A047 atau serupa) – driver bergerak

### Orientasi Penting
```
     ↑ Utara (0°)
     │
     │    [  ]  ← Depan mobil di asset = arah SELATAN (ke bawah)
     │   /   \
     │  |  🚗  |   Asset: mobil menghadap ke bawah
     │   \___/
     │
```

---

## Sumber Icon Gratis

1. **Iconfinder** – Cari "car top view", "vehicle marker", filter PNG
2. **Flaticon** – "car icon map", "navigation car"
3. **Icons8** – "car", "vehicle", pilih style "outline" atau "filled"
4. **CleanPNG** – "uber car", "grab car" (cek lisensi)

**Kata kunci:** car top view, vehicle marker, map car icon, navigation car, ride sharing car

---

## Langkah Penggantian

### 1. Siapkan file baru
- Export PNG 96×96 atau 128×128
- Pastikan background transparan
- Rotasi: depan mobil menghadap ke bawah (selatan)

### 2. Ganti asset
```
traka/assets/images/
├── car_merah.png   ← Ganti dengan file baru
└── car_hijau.png   ← Ganti dengan file baru
```

### 3. (Opsional) Buat varian warna
Jika icon asli berwarna netral (abu/putih), bisa pakai satu file dan tint di kode. Saat ini Traka memakai 2 file terpisah.

### 4. Verifikasi
- Jalankan app
- Cek rotasi ikon saat driver bergerak
- Cek ketajaman di layar retina

---

## Troubleshooting

| Masalah | Solusi |
|---------|--------|
| Ikon menghadap salah arah | Rotasi asset 180° di editor gambar |
| Ikon blur di retina | Gunakan sumber 128×128 px atau lebih |
| Background tidak transparan | Export ulang dengan alpha channel |
| Ukuran terlalu besar/kecil | Kode pakai targetWidth dinamis, sesuaikan di editor |
