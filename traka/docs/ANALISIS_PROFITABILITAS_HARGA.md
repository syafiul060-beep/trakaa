# Analisis Profitabilitas Harga & Biaya Traka

Dokumen ini menganalisis apakah struktur harga/biaya yang diterapkan di aplikasi Traka sudah menguntungkan untuk **pribadi (platform/developer)**, **driver**, dan **pihak lain (penumpang, pengirim barang)**.

---

## 1. Ringkasan Struktur Harga Saat Ini

### 1.1 Sumber Pendapatan Platform (Traka)

| Sumber | Nominal | Pembayar | Mekanisme |
|--------|---------|----------|-----------|
| **Kontribusi driver** | Harga di Play Console (mis. Rp 5.000–10.000) | Driver | Google Play IAP per 1× kapasitas mobil |
| **Lacak Driver** | Rp 3.000 (min, Google Play) | Penumpang | Google Play IAP per order |
| **Lacak Barang** | Rp 10.000 / 15.000 / 25.000 | Pengirim & penerima | Google Play IAP per order |
| **Denda pelanggaran** | Rp 5.000 (min) | Driver/penumpang yang tidak scan | Google Play IAP |

### 1.2 Yang Bukan Pendapatan Platform

- **agreedPrice** (harga kesepakatan perjalanan): dibayar **langsung tunai** dari penumpang ke driver. Platform **tidak mengambil potongan**.
- **tarifPerKm** (Rp 70–85): dipakai untuk menghitung `tripFareRupiah` yang ditampilkan sebagai "Kontribusi Aplikasi" di UI. Ini **hanya informasi/referensi**, bukan fee yang dipotong dari agreedPrice. Pembayaran kontribusi driver dilakukan via IAP (harga produk di Play Console), bukan berdasarkan tripFareRupiah.

### 1.3 Konfigurasi (dari Admin Settings)

| Parameter | Rentang/Nilai | Keterangan |
|-----------|---------------|------------|
| tarifPerKm | 70–85 Rp/km | Untuk hitung tripFareRupiah (display) |
| violationFeeRupiah | Min Rp 5.000 | Denda tidak scan barcode |
| lacakDriverFeeRupiah | Min Rp 3.000 | Google Play min Rp 3.000 |
| lacakBarangDalamProvinsiRupiah | Min Rp 10.000 | Dalam provinsi |
| lacakBarangBedaProvinsiRupiah | Min Rp 15.000 | Beda provinsi |
| lacakBarangLebihDari1ProvinsiRupiah | Min Rp 25.000 | >1 provinsi |

---

## 2. Analisis untuk Platform (Pribadi/Developer)

### 2.1 Pendapatan Kotor

- Kontribusi driver, Lacak Driver, Lacak Barang, dan Violation dibayar via Google Play.
- Platform menerima payout dari Google setelah pemotongan fee.

### 2.2 Biaya yang Dikurangi

1. **Google Play fee**: 15% untuk transaksi pertama $1M/tahun; 30% untuk langganan.
2. **Firebase**: Firestore, Cloud Functions, Auth, dll.
3. **Operasional**: maintenance, support, dll.

### 2.3 Perkiraan Pendapatan Kotor & Bersih untuk Developer

**Asumsi harga:**
- Kontribusi driver: Rp 7.500 per 1× kapasitas (harga di Play Console)
- Lacak Driver: Rp 3.000
- Lacak Barang: Rp 10.000 / 15.000 / 25.000 (rata-rata ~Rp 15.000)
- Violation: Rp 5.000

**Google Play fee:** 15% (first $1M/tahun; 30% untuk langganan)

**Firebase (estimasi per bulan):** ~Rp 50.000–150.000 (Firestore, Functions, Auth) tergantung volume.

---

#### Skenario A: Volume Rendah (100 order/bulan)

| Sumber | Jumlah | Satuan | Pendapatan Kotor |
|--------|--------|--------|------------------|
| Kontribusi driver | 25 | × Rp 7.500 | Rp 187.500 |
| Lacak Driver | 40 | × Rp 3.000 | Rp 120.000 |
| Lacak Barang | 15 | × Rp 15.000 | Rp 225.000 |
| Violation | 5 | × Rp 5.000 | Rp 25.000 |
| **Total kotor** | | | **Rp 557.500** |

| Item | Perhitungan | Jumlah |
|------|-------------|--------|
| Pendapatan kotor | | Rp 557.500 |
| Dikurangi Google Play 15% | | −Rp 83.625 |
| **Pendapatan bersih (sebelum Firebase)** | | **Rp 473.875** |
| Dikurangi Firebase (estimasi) | | −Rp 75.000 |
| **Pendapatan bersih (estimasi)** | | **~Rp 399.000/bulan** |

---

#### Skenario B: Volume Sedang (500 order/bulan)

| Sumber | Jumlah | Satuan | Pendapatan Kotor |
|--------|--------|--------|------------------|
| Kontribusi driver | 120 | × Rp 7.500 | Rp 900.000 |
| Lacak Driver | 200 | × Rp 3.000 | Rp 600.000 |
| Lacak Barang | 80 | × Rp 15.000 | Rp 1.200.000 |
| Violation | 25 | × Rp 5.000 | Rp 125.000 |
| **Total kotor** | | | **Rp 2.925.000** |

| Item | Perhitungan | Jumlah |
|------|-------------|--------|
| Pendapatan kotor | | Rp 2.925.000 |
| Dikurangi Google Play 15% | | −Rp 438.750 |
| **Pendapatan bersih (sebelum Firebase)** | | **Rp 2.486.250** |
| Dikurangi Firebase (estimasi) | | −Rp 200.000 |
| **Pendapatan bersih (estimasi)** | | **~Rp 2.286.000/bulan** |

---

#### Skenario C: Volume Tinggi (2.000 order/bulan)

| Sumber | Jumlah | Satuan | Pendapatan Kotor |
|--------|--------|--------|------------------|
| Kontribusi driver | 500 | × Rp 7.500 | Rp 3.750.000 |
| Lacak Driver | 800 | × Rp 3.000 | Rp 2.400.000 |
| Lacak Barang | 350 | × Rp 15.000 | Rp 5.250.000 |
| Violation | 80 | × Rp 5.000 | Rp 400.000 |
| **Total kotor** | | | **Rp 11.800.000** |

| Item | Perhitungan | Jumlah |
|------|-------------|--------|
| Pendapatan kotor | | Rp 11.800.000 |
| Dikurangi Google Play 15% | | −Rp 1.770.000 |
| **Pendapatan bersih (sebelum Firebase)** | | **Rp 10.030.000** |
| Dikurangi Firebase (estimasi) | | −Rp 500.000 |
| **Pendapatan bersih (estimasi)** | | **~Rp 9.530.000/bulan** |

---

#### Ringkasan Perkiraan Developer

| Skenario | Order/bulan | Pendapatan Kotor | Pendapatan Bersih (estimasi) |
|----------|-------------|------------------|------------------------------|
| A (Rendah) | 100 | ~Rp 558.000 | ~Rp 399.000 |
| B (Sedang) | 500 | ~Rp 2.925.000 | ~Rp 2.286.000 |
| C (Tinggi) | 2.000 | ~Rp 11.800.000 | ~Rp 9.530.000 |

*Catatan: Angka bergantung pada volume riil, harga produk di Play Console, dan biaya Firebase aktual.*

### 2.4 Rekomendasi untuk Platform

- **Volume rendah**: Pendapatan platform kecil. Perlu skala (lebih banyak order, driver, penumpang) agar signifikan.
- **Kontribusi driver**: Pastikan harga di Play Console (`traka_contribution_once`) cukup untuk menutup biaya platform per driver. Contoh: Rp 7.500–10.000 per 1× kapasitas wajar.
- **Lacak Driver Rp 3.000**: Sesuai batas minimum Google Play; harga wajar untuk fitur tambahan.
- **Lacak Barang**: Tier Rp 10.000 / 15.000 / 25.000 masuk akal untuk layanan lacak antar provinsi.
- **Violation Rp 5.000**: Cukup sebagai deterrent tanpa memberatkan.

---

## 3. Analisis untuk Driver

### 3.1 Pendapatan Driver

- **agreedPrice**: 100% ke driver (tunai dari penumpang).
- Tarif referensi: jarak × tarifPerKm (Rp 70–85/km). Driver bisa menawar di atas atau di bawah.

### 3.2 Biaya Driver

1. **Kontribusi Traka**: Rp X per 1× kapasitas mobil (mis. 7 penumpang → 1× bayar).
2. **BBM**: ~Rp 10.000–15.000 per liter; konsumsi ~10–12 km/L.
3. **Pemeliharaan kendaraan**: oli, ban, dll.
4. **Denda violation**: Rp 5.000 jika tidak scan/lupa scan.

### 3.3 Contoh Perjalanan 50 km

- Tarif referensi: 50 × Rp 75 = Rp 3.750 (per penumpang).
- agreedPrice bisa Rp 50.000–100.000 untuk 1–2 penumpang (tergantung negosiasi).
- BBM: 50 km ÷ 12 km/L × Rp 14.000 ≈ Rp 58.000.
- Kontribusi: mis. 1× kapasitas 7 penumpang = 1× Rp 7.500 → ~Rp 1.071 per penumpang jika 7 penumpang.

**Kesimpulan untuk driver**: Agar untung, agreedPrice harus menutup BBM + kontribusi + margin. Tarif Rp 70–85/km sebagai acuan wajar jika penumpang penuh; untuk 1–2 penumpang perlu agreedPrice lebih tinggi per km.

---

## 4. Analisis untuk Penumpang & Pengirim Barang

### 4.1 Penumpang (Travel)

- Bayar **agreedPrice** ke driver (tunai).
- Tarif referensi Rp 70–85/km membantu negosiasi harga wajar.
- Lacak Driver Rp 3.000 bersifat opsional; harga terjangkau untuk fitur tambahan.

### 4.2 Pengirim & Penerima (Kirim Barang)

- Lacak Barang Rp 10.000–25.000 per pihak (pengirim dan penerima bisa bayar masing-masing).
- Harga sesuai kompleksitas (dalam provinsi vs antar provinsi).

---

## 5. Inkonsistensi yang Ditemukan

### 5.1 Lacak Driver: Admin vs App ✅ (Sudah diperbaiki)

- **Admin Settings**: default dan min Rp 3.000 (sinkron dengan batas Google Play).
- **App** (`AppConfigService`): min Rp 3.000.
- **Reports**: default Rp 3.000 jika Firestore kosong.

### 5.2 "Kontribusi Aplikasi" di UI

- Di UI driver: `tripFareRupiah × totalPenumpang` ditampilkan sebagai "Kontribusi Aplikasi".
- Pembayaran aktual: via IAP dengan harga tetap per 1× kapasitas (bukan per tripFareRupiah).

**Saran**: Pertimbangkan penjelasan yang lebih jelas di UI bahwa "Kontribusi Aplikasi" adalah referensi tarif, sedangkan pembayaran dilakukan per X penumpang via Google Play.

---

## 6. Kesimpulan & Rekomendasi

### 6.1 Apakah Sudah Menguntungkan?

| Pihak | Status | Catatan |
|-------|--------|---------|
| **Platform** | Bergantung volume | Volume rendah → margin kecil. Perlu skala dan optimasi biaya. |
| **Driver** | Bisa menguntungkan | Jika agreedPrice menutup BBM + kontribusi. Tarif referensi wajar. |
| **Penumpang** | Harga wajar | agreedPrice nego; Lacak Driver Rp 3.000 opsional dan terjangkau. |
| **Pengirim/penerima** | Harga wajar | Lacak Barang tier sesuai jarak. |

### 6.2 Rekomendasi Umum

1. **Platform**: Pantau rasio pendapatan vs biaya Firebase & Google Play. Naikkan harga kontribusi driver jika perlu (mis. Rp 10.000 per 1× kapasitas).
2. **Driver**: Edukasi agar agreedPrice minimal menutup BBM + kontribusi. Tarif Rp 70–85/km cocok untuk perjalanan penuh.
3. **Sinkronisasi**: Samakan `lacakDriverFeeRupiah` min di Admin dengan app (Rp 3.000).
4. **Transparansi**: Perjelas di UI perbedaan antara "Kontribusi Aplikasi" (referensi) dan pembayaran via Google Play.

---

*Dokumen ini dibuat berdasarkan analisis kode dan konfigurasi di repositori Traka. Angka contoh bersifat ilustratif; sesuaikan dengan data riil dan kebijakan bisnis.*
