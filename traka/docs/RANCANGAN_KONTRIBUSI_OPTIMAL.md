# Rancangan Kontribusi Optimal Traka

Rancangan model kontribusi yang seimbang: platform untung (Firebase + margin), driver tidak terbebani.

---

## 1. Tujuan

| Aspek | Target |
|-------|--------|
| **Platform** | Cukup untuk Firebase, Google Play fee, dan margin kecil |
| **Driver** | Kontribusi proporsional, transparan, tidak memberatkan |
| **Implementasi** | Sederhana, selaras dengan produk Google Billing |

---

## 2. Perhitungan Kontribusi Travel

### 2.1 Rumus Utama (Per Penumpang)

Setiap penumpang punya jarak dan tier berbeda. Kontribusi dihitung **per penumpang** lalu dijumlahkan.

```
Untuk setiap penumpang i:
  jarak_i    = jarak naik → turun penumpang i (km)
  tier_i     = dalam provinsi | antar provinsi | lintas pulau
  tarif_i    = tarifPerKm[tier_i]
  base_i     = max(jarak_i × tarif_i, minKontribusiTravelRupiah)

tripTravelContributionRupiah = base_1 + base_2 + ... + base_n
```

### 2.2 Fallback (Data Terbatas)

Jika jarak per penumpang tidak tersedia:

```
jarakRata = jarakTotalTrip / totalPenumpang
tripTravelContributionRupiah = totalPenumpang × max(jarakRata × tarif[tier_trip], minKontribusiTravelRupiah)
```

### 2.3 Fallback Minimal

Jika data sangat terbatas (koordinat null, dll):

```
tripTravelContributionRupiah = totalPenumpang × minKontribusiTravelRupiah
```

---

## 3. Tier Geografis

| Tier | Kategori | Field Config | Tarif (Rp/km) |
|------|----------|--------------|---------------|
| 1 | Dalam provinsi | `tarifKontribusiTravelDalamProvinsiPerKm` | 90 |
| 2 | Antar provinsi (sama pulau) | `tarifKontribusiTravelBedaProvinsiPerKm` | 110 |
| 3 | Lintas pulau | `tarifKontribusiTravelBedaPulauPerKm` | 140 |

**Logika penentuan tier:**
- Provinsi asal = provinsi tujuan → Tier 1
- Provinsi beda, pulau sama → Tier 2
- Provinsi beda, pulau beda → Tier 3

---

## 4. Konfigurasi Firestore

### 4.1 Field di `app_config/settings`

| Field | Nilai | Keterangan |
|-------|-------|------------|
| `minKontribusiTravelRupiah` | 5000 | Minimum per penumpang |
| `maxKontribusiTravelPerRuteRupiah` | 30000 | Batas maks per rute (opsional) |
| `tarifKontribusiTravelDalamProvinsiPerKm` | 90 | Rp/km, tier 1 |
| `tarifKontribusiTravelBedaProvinsiPerKm` | 110 | Rp/km, tier 2 |
| `tarifKontribusiTravelBedaPulauPerKm` | 140 | Rp/km, tier 3 |

### 4.2 Contoh JSON

```json
{
  "minKontribusiTravelRupiah": 5000,
  "maxKontribusiTravelPerRuteRupiah": 30000,
  "tarifKontribusiTravelDalamProvinsiPerKm": 90,
  "tarifKontribusiTravelBedaProvinsiPerKm": 110,
  "tarifKontribusiTravelBedaPulauPerKm": 140
}
```

### 4.3 Penerapan Batas Maks

```
tripTravelContributionRupiah = min(totalRaw, maxKontribusiTravelPerRuteRupiah)
```

---

## 5. Produk Google Billing

### 5.1 Daftar Produk Kontribusi

| ID Produk | ID Opsi Pembelian | Harga |
|-----------|-------------------|-------|
| `traka_driver_dues_5000` | `traka-driver-dues-5000` | Rp 5.000 |
| `traka_driver_dues_7500` | `traka-driver-dues-7500` | Rp 7.500 |
| `traka_driver_dues_10000` | `traka-driver-dues-10000` | Rp 10.000 |
| `traka_driver_dues_12500` | `traka-driver-dues-12500` | Rp 12.500 |
| `traka_driver_dues_15000` | `traka-driver-dues-15000` | Rp 15.000 |
| `traka_driver_dues_20000` | `traka-driver-dues-20000` | Rp 20.000 |
| `traka_driver_dues_25000` | `traka-driver-dues-25000` | Rp 25.000 |
| `traka_driver_dues_30000` | `traka-driver-dues-30000` | Rp 30.000 |
| `traka_driver_dues_40000` | `traka-driver-dues-40000` | Rp 40.000 |
| `traka_driver_dues_50000` | `traka-driver-dues-50000` | Rp 50.000 |

### 5.2 Logic Pemilihan Produk

```
driverDuesProductTiers = [5000, 7500, 10000, 12500, 15000, 20000, 25000, 30000, 40000, 50000]
productId = pilih tier terkecil dimana tier >= totalKewajiban
```

---

## 6. Data yang Dibutuhkan

### 6.1 Per Order / Per Penumpang

| Field | Sumber | Keterangan |
|-------|--------|------------|
| `tripDistanceKm` | Dihitung dari koordinat | Jarak naik→turun |
| `originProvince` | Geocoding / input | Untuk tier |
| `destinationProvince` | Geocoding / input | Untuk tier |
| `originIsland` / `destinationIsland` | Mapping provinsi→pulau | Opsional, untuk tier 2 vs 3 |

### 6.2 Mapping Provinsi → Pulau

Disimpan di `app_config/provinces` atau hardcode. Contoh:

| Provinsi | Pulau |
|----------|-------|
| DKI Jakarta, Jawa Barat, Banten, Jawa Tengah, DIY, Jawa Timur | Jawa |
| Aceh, Sumatera Utara, Sumatera Barat, Riau, Jambi, Sumatera Selatan, Lampung, dll | Sumatra |
| Bali, NTB, NTT | Nusa Tenggara |
| Kalimantan Barat, Kalimantan Tengah, Kalimantan Selatan, Kalimantan Timur, Kalimantan Utara | Kalimantan |
| Sulawesi Utara, Gorontalo, Sulawesi Tengah, Sulawesi Barat, Sulawesi Selatan, Sulawesi Tenggara | Sulawesi |
| Maluku, Maluku Utara | Maluku |
| Papua, Papua Barat, Papua Selatan, Papua Tengah, Papua Pegunungan | Papua |

---

## 7. Contoh Perhitungan

### Contoh 1: 3 penumpang, jarak berbeda

| Penumpang | Jarak | Tier | Tarif | Base |
|-----------|-------|------|-------|------|
| A | 150 km | Antar provinsi | 110 | 16.500 |
| B | 80 km | Antar provinsi | 110 | 8.800 |
| C | 120 km | Antar provinsi | 110 | 13.200 |
| **Total** | | | | **38.500** |

Dibatasi max: min(38.500, 30.000) = **Rp 30.000** → produk `traka_driver_dues_30000`

### Contoh 2: 1 penumpang, dalam provinsi

| Penumpang | Jarak | Tier | Tarif | Base |
|-----------|-------|------|-------|------|
| A | 40 km | Dalam provinsi | 90 | max(3.600, 5.000) = 5.000 |
| **Total** | | | | **5.000** |

→ produk `traka_driver_dues_5000`

### Contoh 3: Fallback rata-rata (2 penumpang, 100 km total)

```
jarakRata = 100 / 2 = 50 km
base = max(50 × 110, 5.000) = 5.500
Total = 2 × 5.500 = 11.000
```

→ produk `traka_driver_dues_12500`

---

## 8. Alur Pembayaran

1. Driver selesai rute → `route_sessions` disimpan dengan `contributionRupiah`
2. Total kewajiban = travel (route_sessions) + barang + pelanggaran
3. App tampilkan total kewajiban dan produk terdekat (bulat ke atas)
4. Driver bayar via Google Play IAP
5. Cloud Function verifikasi → update `contributionPaidAt` / `contribution*PaidUpToRupiah`

---

## 9. Prioritas Pendapatan Platform

| Sumber | Prioritas | Estimasi |
|--------|-----------|----------|
| Lacak Barang | Tinggi | Rp 10.000–25.000 per order |
| Lacak Driver | Sedang | Rp 3.000 per order |
| Kontribusi driver | Sedang | Rp 5.000–30.000 per rute |
| Pelanggaran | Rendah | Rp 5.000 per kejadian |

---

## 10. Checklist Implementasi

- [x] Update `app_config/settings` dengan field baru (max, tarif 90/110/140)
- [ ] Buat produk `traka_driver_dues_5000` dan `traka_driver_dues_10000` di Play Console
- [x] Update logic perhitungan: batas max per rute diterapkan di `getTotalContributionRupiahForRoute`
- [x] Mapping provinsi → pulau: pakai LacakBarangService.getTierAndFee (tier 1/2/3)
- [x] Update logic pemilihan produk (tambah 5000, 10000 ke daftar tier)
- [x] Update `UPDATE_HARGA_GOOGLE_BILLING.md` dengan produk baru
- [x] Update `KONTRIBUSI_TRAVEL_CONFIG.md` dengan rumus baru

---

## 11. Referensi

- `docs/UPDATE_HARGA_GOOGLE_BILLING.md` — Tabel produk Play Console
- `docs/KONTRIBUSI_TRAVEL_CONFIG.md` — Config Firestore (perlu diupdate)
- `docs/CEK_KONTRIBUSI_DAN_PEMBAYARAN.md` — Alur pembayaran
- `docs/ANALISIS_PROFITABILITAS_HARGA.md` — Analisis pendapatan vs biaya
