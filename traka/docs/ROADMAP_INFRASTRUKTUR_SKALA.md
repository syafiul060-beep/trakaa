# Roadmap infrastruktur & skala (**poin 5**)

**Panduan operasional 4 tahap** (otomatis vs manual, gate, urutan kerja): [`TAHAPAN_MIGRASI_INFRA_4_FASE.md`](TAHAPAN_MIGRASI_INFRA_4_FASE.md). **Tahap 2 (optimasi murah):** [`TAHAPAN_2_Optimasi_Murah.md`](TAHAPAN_2_Optimasi_Murah.md). **Tahap 3 (API + Redis + hybrid):** [`TAHAPAN_3_Scale_API_Redis_Hybrid.md`](TAHAPAN_3_Scale_API_Redis_Hybrid.md). **Tahap 4 (WebSocket / realtime massal):** [`TAHAPAN_4_Realtime_WebSocket.md`](TAHAPAN_4_Realtime_WebSocket.md).

**Prinsip:** tambah kompleksitas hanya setelah **QA** (lihat [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md)) dan **monitoring** ([`../traka-api/docs/MONITORING_PRODUCTION.md`](../traka-api/docs/MONITORING_PRODUCTION.md)) menunjukkan kebutuhan.

**Klaim “siap jutaan pengguna”** (stakeholder + checklist operasional): [`KESIAPAN_SKALA_JUTAAN_PENGGUNA.md`](KESIAPAN_SKALA_JUTAAN_PENGGUNA.md).

## Kapan mempertimbangkan apa

| Gejala / metrik | Arah teknis |
|-----------------|-------------|
| Lokasi driver terasa lambat di peta; polling berat | Worker **WebSocket** + subscribe grid; `REDIS_PUBLISH_DRIVER_LOCATION=1` + consumer ([`REALTIME_DRIVER_UPDATES.md`](../traka-api/docs/REALTIME_DRIVER_UPDATES.md)). |
| Firestore read mahal / lambat | Cache di Redis; kurangi listener lebar. |
| Satu file screen >5k baris sulit dirawat | Pecah widget/stateless parts **tanpa** ubah perilaku sekaligus besar. |
| Dependency usang / CVE | Upgrade **satu paket** per PR + `flutter test` / smoke QA. |

## Urutan disarankan (jangan dibalik)

1. Data dari `/health` + Sentry + laporan QA.
2. Optimasi murah (throttle, limit marker, query).
3. Horizontal scale API + Redis tetap pusat geo.
4. Realtime push massal.

## Status saat ini (fondasi)

- Matching: Redis GEO + skor opsional `destLat`/`destLng`.
- Publish lokasi driver: opsional via env (bukan broadcast penuh ke client).

*Tinjau ulang dokumen ini tiap kuartal atau setelah lonjakan pengguna.*
