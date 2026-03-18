# Tahap 3 – Optimasi Driver Status

## Yang Diterapkan

**Pagination pada `GET /api/driver/status`** – menghindari full SCAN Redis saat ada ribuan driver.

### Sebelum
- Full SCAN semua key `driver_status:*`
- N kali GET (satu per driver)
- Response lambat saat 1000+ driver

### Sesudah
- SCAN dengan cursor + limit
- Batch GET (mGet) untuk efisiensi
- Response: max 50–100 driver per request
- Client bisa pagination untuk data lebih banyak

---

## API

```
GET /api/driver/status?limit=50&cursor=0
```

| Query   | Default | Max  | Keterangan                    |
|---------|---------|------|-------------------------------|
| `limit` | 50      | 100  | Jumlah driver per response    |
| `cursor`| 0       | -    | Untuk halaman berikutnya     |

**Response:**
```json
{
  "drivers": [...],
  "nextCursor": 12345
}
```

- `nextCursor: null` = tidak ada halaman berikutnya
- `nextCursor: number` = gunakan untuk request berikutnya: `?cursor=12345`

---

## Backward Compatibility

Client yang tidak mengirim `limit`/`cursor` akan mendapat 50 driver pertama (default). Response tetap punya `drivers` array.

---

## Opsi Lanjutan (belum diimplementasi)

Untuk filter by region/lokasi, bisa tambah Geo Hash + Sorted Set (lihat `docs/CHECKLIST_SCALING_DAN_MONITORING.md` bagian Opsi A).
