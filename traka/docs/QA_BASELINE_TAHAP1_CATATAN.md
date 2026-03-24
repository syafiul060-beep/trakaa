# QA baseline — Tahap 1 (catatan sesi)

File ini memenuhi **“QA minimal + catatan”** untuk penutupan Tahap 1 observabilitas.  
Rujukan: [`QA_BASELINE_TAHAP1_TEMPLATE.md`](QA_BASELINE_TAHAP1_TEMPLATE.md), [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md) (matriks lengkap untuk rilis besar).

---

## Metadata

| Field | Nilai |
|-------|--------|
| Tanggal | 2026-03-21 |
| Versi app (version+build) | <!-- isi dari Pengaturan / About setelah uji A1 --> |
| Platform | Android / iOS (sesuaikan) |
| API / Redis | on |
| Tester | <!-- nama Anda --> |
| URL `/health` produksi | `https://trakaa-production.up.railway.app/health` |

---

## Hasil minimal

| ID | Skenario | Lulus? |
|----|----------|--------|
| F1 | `GET /health` → `ok: true`, ada `version` | **Lulus** (2026-03-21): respons JSON memuat `version` dan `uptimeSeconds`; `checks.api/redis/pg` true sesuai deploy Railway. |
| A1 | Login penumpang → beranda peta tampil | [ ] <!-- centang setelah satu kali uji di perangkat --> |

**Catatan singkat:**

- Tidak ada anomaly pada endpoint `/health` untuk gate Tahap 1.
- UptimeRobot + UptimeRobot monitor ke `/health` aktif (sesuai setup Tahap 1).
- Sentry menerima event (Issues terlihat di dashboard).

---

## Tanda selesai Tahap 1 (QA)

- [x] Metadata + **F1** terdokumentasi.
- [ ] **A1** (opsional tapi disarankan): centang setelah smoke test di app.
- [ ] Isi **Versi app** dan **Tester** di tabel metadata di atas.

Setelah itu, Tahap 1 dari sisi QA **minimal** dapat ditutup.
