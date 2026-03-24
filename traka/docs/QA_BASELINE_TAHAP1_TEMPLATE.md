# QA baseline — Tahap 1 (minimal, satu sesi)

Salin file ini atau isi langsung di bawah, lalu simpan (Notion / commit pribadi / arsip tim).

**Tujuan:** memenuhi **“QA sekali + catatan”** untuk [`TAHAPAN_1_OBSERVABILITAS.md`](../traka-api/docs/TAHAPAN_1_OBSERVABILITAS.md) tanpa menjalankan seluruh matriks [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md).

---

## Metadata

| Field | Nilai |
|-------|--------|
| Tanggal | <!-- isi --> |
| Versi app (version+build) | <!-- dari Pengaturan / About --> |
| Platform | Android / iOS |
| API / Redis | on |
| Tester | <!-- nama Anda --> |
| URL `/health` produksi | `https://trakaa-production.up.railway.app/health` |

---

## Centang minimal (cukup untuk Tutup Tahap 1)

| ID | Skenario | Lulus? |
|----|----------|--------|
| F1 | `GET /health` di browser → `ok: true`, ada `version` | [ ] |
| A1 | (Opsional tapi disarankan) Login penumpang → beranda peta tampil | [ ] |

**Catatan singkat / anomaly (jika ada):**

```
<!-- tulis di sini, atau "tidak ada" -->
```

---

## Tanda selesai

- [ ] File ini atau salinannya tersimpan dengan **tanggal** dan minimal **F1** terisi.
- [ ] Sentry: `SENTRY_DSN` sudah di Railway dan redeploy sukses (lihat dokumen Tahap 1).

*Untuk regresi penuh sebelum rilis besar, gunakan [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md).*
