# Target navigasi: Traka vs parity Google Maps

Dokumen ini memisahkan **dua target** yang sering dicampur — supaya ekspektasi, biaya API, dan pilihan teknologi selaras.

---

## Prinsip produk: navigasi **tetap di aplikasi Traka**

**Mengikuti rute dan arahan perjalanan harus dapat dilakukan di dalam aplikasi** — driver tidak ditargetkan untuk *bergantung* pada membuka Google Maps / Waze untuk menjalankan travel normal. Peningkatan teknis (Target A maupun evaluasi Navigation SDK) mengarah ke pengalaman **in-app**: reroute, polyline, suara, dan (jika suatu saat) SDK navigasi **tertanam** di Traka — bukan mengganti inti alur dengan “buka di app lain”.

---

## Target A — “Cukup untuk driver Traka” (stack sekarang)

**Tujuan:** Driver dapat mengikuti rute ke tujuan/penumpang dengan aman dan jelas, dalam konteks aplikasi mitra Traka (bukan menggantikan app navigasi consumer).

**Cakupan yang masuk akal dengan `google_maps_flutter` + Directions API + logika di app:**

| Area | Yang dikejar |
|------|----------------|
| Rute | Garis di peta, alternatif, ETA, reroute otomatis saat menyimpang |
| Posisi | Snap/unsnap sesuai kebijakan, ikon diam/bergerak, bearing |
| Suara | Instruksi per step (TTS), bisa dimatikan |
| Belokan terlewat | Heuristik (jarak ke polyline + step + jendela setelah manuver) |
| Performa | Throttle kamera, debounce API, hindari UI macet saat fetch |

**Batasan yang diterima:** Tidak harus sama persis dengan **aplikasi Google Maps** di Play Store (lane, timing suara, animasi, dsb.).

**Kapan pilih Target A:** Fokus produk Traka adalah order, penumpang, dan operasional — navigasi adalah **pendukung** yang kuat, bukan produk navigasi mandiri.

---

## Target B — “Identik / selevel app Google Maps untuk navigasi”

**Tujuan:** Pengalaman turn-by-turn **seperti** app Google Maps (lane, instruksi rapat, perilaku reroute internal, dsb.).

**Secara praktis biasanya mengarah ke:**

- **Google Navigation SDK** (Android / iOS) dengan integrasi ke Flutter (platform channel / plugin yang mendukung), **atau**
- Invest besar di **data + UX** untuk meniru fitur lane / persimpangan kompleks (sering tidak masuk akal tanpa produk khusus).

**Implikasi:**

| Aspek | Catatan |
|-------|
| Biaya & lisensi | Navigation SDK punya syarat dan biaya tersendiri; verifikasi di Google Cloud / kontrak |
| Engineering | Integrasi native, uji perangkat, pemeliharaan versi SDK |
| Parity | Mendekati app Google; tetap bukan “copy paste” binary |

**Kapan pilih Target B:** Ada keputusan produk eksplisit bahwa Traka harus **bersaing** sebagai app navigasi utama driver, atau regulasi/UX mewajibkan parity setinggi itu.

---

## Kalau **A dan B** keduanya diinginkan

Itu bukan “pilih salah satu” dalam arti membuang yang lain — artinya **dua lapis** dengan peran beda:

| Lapisan | Peran | Catatan |
|--------|--------|--------|
| **A (tetap)** | Navigasi **bawaan** Traka: beranda, rute kerja, order, snap, reroute, missed-turn — **tanpa** Navigation SDK | Ini yang dipakai mayoritas alur; **tetap** diperbaiki dan dipelihara. |
| **B (tambahan)** | Mode atau layar **khusus** “navigasi penuh” mendekati Google Maps — via Navigation SDK / integrasi native | Bukan mengganti A di semua layar sekaligus; biasanya **opsional** atau fase tertentu. |

**Yang realistis secara produk:**

1. **Jangan** menjalankan dua mesin navigasi penuh **bersamaan** di **satu** layar peta (dua sumber bearing + dua suara) tanpa desain yang sangat jelas — rawan bentrok dan boros baterai/API.
2. **Urutan umum:** **A** stabil dulu → **B** sebagai **tambahan** (mis. tombol “Buka navigasi lanjutan” / otomatis hanya saat mode tertentu) setelah spike SDK.
3. **Biaya tim:** A = Flutter utama; B = + native Android/iOS + QA perangkat + lisensi — **dua jalur pemeliharaan**.

**Ringkas:** **A = fondasi Traka; B = opsi premium / parity** jika budget dan keputusan produk mengizinkan. Bukan “A atau B” melulu, tapi **A wajib jalan, B bisa menyusul** tanpa mematikan A.

---

## Matriks keputusan (ringkas)

| Pertanyaan | Kalau jawabannya… |
|------------|-------------------|
| Apakah travel normal harus bisa dari **satu app (Traka)** tanpa wajib pindah ke navigasi lain? | **Ya (prinsip produk)** — tingkatkan Target A; Target B = SDK **di dalam** Traka |
| Apakah navigasi dalam app adalah **differentiator** utama vs kompetitor? | Pertimbangkan Target B |
| Apakah budget API + tim native untuk SDK masuk akal? | Target B |
| Fokus utama: order, chat, kepatuhan rute operasional? | Target A |

---

## Rekomendasi default Traka

- **Default produk:** **Target A** — terus perbaiki heuristik reroute, missed turn, UX loading rute, dan akurasi lokasi.
- **Target B** hanya setelah **keputusan tertulis** (produk + biaya + legal) + spike teknis Navigation SDK (1–2 sprint eksplorasi).

---

## Langkah eksekusi **langsung** (urutan kerja)

### Fase 1 — Target A (lanjutkan, tanpa tunggu B)

1. **Regresi di perangkat nyata** — rute utama, navigasi ke penumpang, reroute otomatis, missed-turn, snap 95 m (Kalimantan / jalan baru).
2. **Pantau Directions API** — kuota, error `OVER_QUERY_LIMIT`, cache di `directions_service.dart`.
3. **UX saat rute baru** — jika masih terasa macet, catat skenario (HP lemah / jaringan) untuk optimasi terpisah (bukan blok fitur).
4. **Suara** — pastikan mute/driver preference tetap jalan; instruksi tidak dobel setelah hydrate steps.

### Fase 2 — Target B (hanya setelah keputusan produk + biaya)

1. **Kontrak & konsol** — cek syarat **Navigation SDK** di dokumentasi Google (lisensi, billing, pembatasan pakai).
2. **Spike 1–2 sprint** — project Android kecil saja: tampilkan peta navigasi SDK di activity terpisah; belum Flutter.
3. **Flutter** — platform channel atau plugin yang sudah ada; POC satu tombol “Navigasi lanjutan (beta)” dari `driver_screen` (opsional).
4. **Produk** — Navigation SDK **tertanam** di Traka (layar / mode khusus), bukan mengganti dengan deep link ke app Google Maps untuk inti alur.

### A + B bersamaan (tanpa bentrok)

- **Default:** selalu **A** di beranda / order.
- **B** hanya lewat **entry point terpisah** (layar/modal) sampai terbukti stabil; matikan suara/tracking A saat B aktif jika keduanya pernah hidup berurutan.

---

## Referensi teknis di repo

- Perilaku kamera, snap, reroute: `lib/screens/driver_screen.dart`, `docs/` terkait peta (jika ada).
- Directions API: `lib/services/directions_service.dart`.

---

*Dokumen ini untuk alignment internal; bukan janji fitur ke pengguna akhir.*
