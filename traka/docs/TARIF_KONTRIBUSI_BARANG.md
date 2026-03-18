# Tarif Kontribusi Kirim Barang (per Kategori)

Kontribusi driver untuk order **kirim barang** dihitung dari jarak efektif × tarif per km, dengan tarif berbeda untuk **Dokumen** dan **Kargo**.

---

## Rumus

`tripBarangFareRupiah = jarak_efektif (km) × tarif_per_km (Rp)`

Jarak efektif = jarak pickup → drop minus jarak kapal/ferry (jika ada).

---

## Kategori Barang

| Kategori | Deskripsi | Default tarif (Rp/km) |
|----------|------------|------------------------|
| **Dokumen** | Surat, amplop, paket kecil | Tier 1: 10, Tier 2: 25, Tier 3: 35 |
| **Kargo** | Paket dengan berat/dimensi | Tier 1: 15, Tier 2: 35, Tier 3: 50 |

Order lama tanpa `barangCategory` diperlakukan sebagai **Kargo**.

---

## Tier Provinsi

- **Tier 1**: Asal dan tujuan dalam provinsi yang sama
- **Tier 2**: Beda provinsi
- **Tier 3**: Lebih dari 1 provinsi (lintas provinsi)

---

## Mengubah Tarif

### Via Web Admin (disarankan)

1. Login ke **traka-admin**
2. Buka **Settings** → scroll ke bagian **Kontribusi kirim barang**
3. Atur nilai **Kargo** dan **Dokumen** per tier provinsi
4. Klik **Simpan Semua**

### Via Firestore (manual)

Buka **Firebase Console → Firestore** → `app_config` / `settings`.

### Tarif Kargo (default)

| Field | Default | Keterangan |
|-------|---------|------------|
| `tarifBarangDalamProvinsiPerKm` | 15 | Rp/km, tier 1 |
| `tarifBarangBedaProvinsiPerKm` | 35 | Rp/km, tier 2 |
| `tarifBarangLebihDari1ProvinsiPerKm` | 50 | Rp/km, tier 3 |

### Tarif Dokumen (opsional)

| Field | Default | Keterangan |
|-------|---------|------------|
| `tarifBarangDokumenDalamProvinsiPerKm` | 10 | Rp/km, tier 1 |
| `tarifBarangDokumenBedaProvinsiPerKm` | 25 | Rp/km, tier 2 |
| `tarifBarangDokumenLebihDari1ProvinsiPerKm` | 35 | Rp/km, tier 3 |

### Contoh `app_config/settings`

```json
{
  "tarifBarangDalamProvinsiPerKm": 15,
  "tarifBarangBedaProvinsiPerKm": 35,
  "tarifBarangLebihDari1ProvinsiPerKm": 50,
  "tarifBarangDokumenDalamProvinsiPerKm": 10,
  "tarifBarangDokumenBedaProvinsiPerKm": 25,
  "tarifBarangDokumenLebihDari1ProvinsiPerKm": 35
}
```

Jika field dokumen tidak diisi, app memakai default (10/25/35 Rp/km).

---

## Kapan Dihitung

`tripBarangFareRupiah` dihitung saat **penerima scan barcode** (order kirim barang selesai). Nilai ini menambah `totalBarangContributionRupiah` driver yang harus dibayar via kontribusi gabungan.
