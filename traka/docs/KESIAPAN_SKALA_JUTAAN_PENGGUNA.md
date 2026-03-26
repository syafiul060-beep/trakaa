# Kesiapan skala (jutaan pengguna)—checklist & kalimat stakeholder

Dokumen ini melengkapi [`ROADMAP_INFRASTRUKTUR_SKALA.md`](ROADMAP_INFRASTRUKTUR_SKALA.md) dan [`TAHAPAN_MIGRASI_INFRA_4_FASE.md`](TAHAPAN_MIGRASI_INFRA_4_FASE.md): **apa yang boleh diklaim** ke investor/stakeholder tanpa overselling, dan **apa yang harus dibuktikan** dulu.

---

## Satu kalimat untuk stakeholder

**Fitur alur penumpang–driver (peta, chat, pesan, lacak, barcode) didukung arsitektur hybrid + Firebase; “siap untuk 1–5 juta pengguna” secara operasional baru dapat dipertanggungjawabkan setelah metrik produksi, uji beban, dan gate tahap skala (Tahap 1–4) terpenuhi—bukan hanya karena alur fitur sudah jalan di internal.**

_(Sesuaikan angka “1–5 juta” dengan konteks: akun terdaftar vs bulanan aktif vs puncak konkuren.)_

---

## Istilah yang sering salah kaprah

| Yang diucapkan | Yang sebenarnya menekan sistem |
|----------------|--------------------------------|
| “5 juta download” | Bukan semua buka app bersamaan; puncak **konkuren** dan **RPS** yang penting. |
| “5 juta user aktif” | Bedakan **MAU/DAU** vs **sesi peta + update lokasi/menit** + **chat/order**. |
| “Aman dipakai” | Gabungan **keamanan data**, **stabilitas**, **biaya** Firebase/API/Redis, dan **kepatuhan** (privasi, retensi). |

---

## Alur produk yang dimaksud (referensi QA)

Cari driver aktif di peta → ketuk ikon mobil → chat / kesepakatan → lanjut pesan atau tidak → lacak driver–barang–link → scan barcode → pesanan selesai. Regresi hybrid: [`QA_HYBRID_REGRESI.md`](QA_HYBRID_REGRESI.md); alur umum: [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md).

---

## Fokus operasional (mulai dari sini)

**Jika waktu terbatas**, kerjakan berurutan:

1. Buka [`QA_HYBRID_REGRESI.md`](QA_HYBRID_REGRESI.md) → isi tabel **Sesi uji** (tanggal, `TRAKA_API_BASE_URL`, commit/tag API, build app).
2. Selesaikan **Smoke API pasca-deploy** sampai **PASS** (health, TLS, admin/CORS sesuai env).
3. Jalankan **seluruh tabel skenario** hybrid sekali penuh pada **build + URL API yang sama** dengan yang dipakai produksi; isi **Ringkasan sesi** (PASS/FAIL, blocker).
4. Kembali ke **Checklist** di bawah; centang item yang sudah terbukti di production.

**Setelah itu (bertahap):** catat baseline **error / latensi / biaya Firestore**; rencanakan **uji beban** sebelum kampanye besar; naikkan `DRIVER_LOCATION_RATE_LIMIT_PER_MIN` di Railway **hanya sementara** untuk load test (lalu turunkan lagi); jika peta/lokasi berat, jangan loncat tahap—ikuti [`ROADMAP_INFRASTRUKTUR_SKALA.md`](ROADMAP_INFRASTRUKTUR_SKALA.md) / [`TAHAPAN_MIGRASI_INFRA_4_FASE.md`](TAHAPAN_MIGRASI_INFRA_4_FASE.md).

---

## Checklist sebelum klaim “siap jutaan” (operasional)

Centang yang sudah terbukti di **lingkungan production** (bukan hanya staging):

- [ ] **Tahap 1 — Observabilitas:** `/health` + uptime + (disarankan) Sentry API — [`../traka-api/docs/TAHAPAN_1_OBSERVABILITAS.md`](../traka-api/docs/TAHAPAN_1_OBSERVABILITAS.md), [`../traka-api/docs/MONITORING_PRODUCTION.md`](../traka-api/docs/MONITORING_PRODUCTION.md).
- [ ] **Deploy API konsisten:** commit/tag API diketahui; redeploy & env jelas — [`../traka-api/docs/RAILWAY_DEPLOY_CEPAT.md`](../traka-api/docs/RAILWAY_DEPLOY_CEPAT.md).
- [ ] **Hybrid QA:** smoke health + skenario utama hybrid lulus — [`QA_HYBRID_REGRESI.md`](QA_HYBRID_REGRESI.md).
- [ ] **Firestore indeks (Cari travel / fallback):** indeks komposit `driver_status` (`status` + `lastUpdated`) di repo sudah **ter-deploy** ke project production (`firebase deploy --only firestore:indexes` dari folder `traka/`) — [`FIREBASE_DEPLOY_CEPAT.md`](FIREBASE_DEPLOY_CEPAT.md); catatan query di [`QA_HYBRID_REGRESI.md`](QA_HYBRID_REGRESI.md) (bagian *Catatan teknis*).
- [ ] **Beban & biaya:** estimasi atau hasil uji untuk **Firestore read/write**, **lokasi driver**, **API** (rate limit lokasi: `DRIVER_LOCATION_RATE_LIMIT_PER_MIN` di Railway), **Redis**; revisi jika lonjakan.
- [ ] **Gate tahap roadmap:** setelah gejala muncul (peta lambat, read mahal), ikuti urutan Tahap 2 → 3 → 4 — jangan loncat — [`TAHAPAN_MIGRASI_INFRA_4_FASE.md`](TAHAPAN_MIGRASI_INFRA_4_FASE.md).
- [ ] **Realtime massal:** puncak lokasi + banyak klien peta → siapkan arah WebSocket/worker sesuai [`../traka-api/docs/REALTIME_DRIVER_UPDATES.md`](../traka-api/docs/REALTIME_DRIVER_UPDATES.md) / [`TAHAPAN_4_Realtime_WebSocket.md`](TAHAPAN_4_Realtime_WebSocket.md).

**Uji beban:** pakai skrip atau vendor yang mencerminkan **RPS** dan pola nyata (bukan hanya satu `curl`). Dokumentasikan angka: konkuren, error rate, p95 latensi, biaya per menit jika bisa.

---

## Kapan meninjau ulang

Setelah **lonjakan kampanye**, **rilis besar**, atau **tiap kuartal**—sesuai catatan di roadmap skala.
