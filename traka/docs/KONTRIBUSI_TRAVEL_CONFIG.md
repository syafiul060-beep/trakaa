# Kontribusi Travel Berbasis Jarak × Penumpang

Kontribusi driver untuk order **travel** dihitung dari **totalPenumpang × (jarak × tarif per km, min Rp 5.000)**. Nilai diambil dari jarak penumpang, bukan default. Per rute dibatasi max Rp 30.000 agar tidak memberatkan driver.

---

## Rumus

`basePerPenumpang = max(jarak × tarifPerKm, minKontribusiTravelRupiah)`  
`tripTravelContributionRupiah = min(totalPenumpang × basePerPenumpang, maxKontribusiTravelPerRuteRupiah)`

- **Dasar** dari jarak: 52 km × Rp 90/km = Rp 4.680 → min Rp 5.000
- **Penumpang sendiri** (1 orang): 1 × 5.000 = Rp 5.000
- **Kerabat** (3 orang): 3 × 5.000 = Rp 15.000 (dalam provinsi)

---

## Konfigurasi Firestore

Buka **Firebase Console → Firestore** → `app_config` / `settings`.

| Field | Default | Keterangan |
|-------|---------|------------|
| `minKontribusiTravelRupiah` | 5000 | Minimum Rp (jika jarak × tarif < min) |
| `maxKontribusiTravelPerRuteRupiah` | 30000 | Batas maks per rute (opsional) |
| `tarifKontribusiTravelDalamProvinsiPerKm` | 90 | Rp/km, tier 1 |
| `tarifKontribusiTravelBedaProvinsiPerKm` | 110 | Rp/km, tier 2 |
| `tarifKontribusiTravelBedaPulauPerKm` | 140 | Rp/km, tier 3 |

### Contoh `app_config/settings`

```json
{
  "minKontribusiTravelRupiah": 5000,
  "maxKontribusiTravelPerRuteRupiah": 30000,
  "tarifKontribusiTravelDalamProvinsiPerKm": 90,
  "tarifKontribusiTravelBedaProvinsiPerKm": 110,
  "tarifKontribusiTravelBedaPulauPerKm": 140
}
```

---

## Field Users (otomatis)

- `totalTravelContributionRupiah`: Akumulasi kontribusi travel dari order selesai
- `contributionTravelPaidUpToRupiah`: Sudah dibayar sampai nilai ini

---

## IAP Product (Play Console)

Produk kontribusi: 5.000, 7.500, 10.000, 12.500, 15.000, 20.000, 25.000, 30.000, 40.000, 50.000. Lihat `UPDATE_HARGA_GOOGLE_BILLING.md`.

---

## Oper Driver

Saat driver kedua scan transfer, driver pertama dapat kontribusi flat = `minKontribusiTravelRupiah` (default Rp 5.000).
