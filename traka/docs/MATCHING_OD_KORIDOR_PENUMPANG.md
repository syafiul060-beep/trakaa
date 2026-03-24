# Matching penumpang ↔ driver «searah» (OD + koridor)

Dokumen ini menjelaskan **perilaku produk dan teknis** saat penumpang mencari travel (driver `siap_kerja` di peta), supaya selaras dengan cara driver memilih rute di peta (termasuk **jalan alternatif** ke tujuan yang sama).

---

## Prinsip

1. **Kunci matching = asal–tujuan operasional driver (OD)** yang tersimpan di `driver_status` (`routeOrigin*`, `routeDest*`), plus metadata seperti **`routeCategory`** jika ada.
2. **Polyline yang dipilih driver** di layar (Rute 1 / 2 / 3) utama untuk **navigasi & UX**; **bukan** satu-satunya garis yang dipakai algoritma «searah» untuk penumpang.
3. **Koridor** = daerah di sekitar **satu atau lebih** polyline hasil Directions API untuk **OD yang sama**. Penumpang lolos filter jika titik **jemput** dan **turun** masing-masing berada dalam **buffer** ke salah satu polyline itu.

Dampaknya: driver boleh memilih alternatif di kota (hindari macet) tanpa mengubah **identitas koridor** «saya dari A menuju B» untuk pencarian penumpang.

---

## Implementasi (ringkas)

- **Layanan:** `ActiveDriversService.getActiveDriversForMapResult` (`lib/services/active_drivers_service.dart`).
- Untuk setiap driver kandidat:
  1. Panggil `DirectionsService.getAlternativeRoutes` dengan **OD driver** → dapat 0…N polyline.
  2. Jika hasil kosong, **fallback** `DirectionsService.getRoute` (satu polyline, OD tetap sama).
  3. Cek penumpang:
     - **Jemput:** jarak titik penumpang ke polyline terdekat ≤ `RouteUtils.defaultToleranceMeters` (saat ini 10 km).
     - **Turun:** ≤ `RouteUtils.passengerDropoffToleranceMeters` (saat ini 25 km — lebih longgar agar tujuan di samping jalur utama tetap lolos).
  4. Aturan tambahan: urutan jemput–turun vs tujuan driver, filter «driver belum lewat penumpang», radius dari penjemputan, dll. (tetap seperti di kode).

**Toleransi** dikonsentrasikan di `RouteUtils` (`lib/services/route_utils.dart`). Referensi konstanta path dokumen: `AppConstants.matchingOdCorridorDocRelative`.

---

## Yang tidak dilakukan (sengaja)

- Matching **tidak** mengunci ke satu polyline bit-exact yang sedang ditampilkan driver.
- **Tidak** mengubah OD penumpang hanya karena driver mengganti alternatif rute di peta.

---

## Penyesuaian ke depan

- Mengubah **buffer** (km): edit konstanta di `RouteUtils` dan uji regresi pencarian di wilayah jarang jalan (Kalimantan) vs kota padat.
- **API match** hybrid (`TrakaApiService.getMatchDrivers`): pastikan server mengikuti prinsip OD + koridor yang sama bila nanti menjadi sumber utama.

---

*Dokumen internal alignment produk–engineering; bukan janji ke pengguna akhir.*
