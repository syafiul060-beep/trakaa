# Dimensi kontribusi driver (referensi CS & produk)

Ringkasan **apa yang memengaruhi nominal** di sistem saat ini. Detail angka mengikuti `app_config/settings` (bukan angka tetap di kode).

## 1. Tier rute (inti)

| Tier | Makna | Sumber teknis |
|------|--------|----------------|
| **1** | Asal & tujuan **satu provinsi** | `LacakBarangService.getTierAndFee` |
| **2** | **Beda provinsi**, masih **satu pulau** | idem |
| **3** | **Beda pulau** (nasional / lintas pulau) | idem |

**Catatan produk:** Label UX seperti “Dalam Kota” vs “Antar Kabupaten” **bukan** tier terpisah untuk kontribusi — jika masih **satu provinsi**, tetap **tier 1**.

## 2. Travel (penumpang)

- **Jarak yang dipakai untuk tarif penumpang dan kontribusi travel** = jarak lurus (Haversine) **dikurangi estimasi segmen ferry/laut** bila lintas pulau (`ferryDistanceKm`), sama seperti `tripFareRupiah` — disimpan `tripDistanceKm` (total lurus), opsional `ferryDistanceKm`, pembebanan memakai **jarak efektif** = `tripDistanceKm − ferry` (dibatasi). Lihat `OrderService._travelKmFerryEffective` (penyelesaian otomatis) dan alur scan dengan `ferryDistanceKm` dari UI.
- **Per penumpang:** `(jarak efektif × tarif/km tier)` dengan minimum per penumpang; lalu **dikalikan jumlah penumpang** (sendiri + kerabat).
- **Cap per rute:** total kontribusi travel untuk **satu sesi rute** (semua order travel di rute itu) dibatasi maksimal (lihat `maxKontribusiTravelPerRuteRupiah`).
- **Estimasi di dialog driver** (`getEstimatedContributionForDriver`): memakai jarak efektif (setelah estimasi ferry) agar selaras dengan penyelesaian.

## 3. Kirim barang

- **Kargo vs dokumen:** tarif/km berbeda (`barangCategory`: `kargo` / `dokumen`).
- **Rumus:** `jarak efektif × tarif/km` sesuai tier + kategori (setelah kurangi ferry, sama seperti `tripBarangFareRupiah`; estimasi driver memakai `_travelKmFerryEffective`).

## 4. Pelanggaran

- **Satu nominal per kejadian** (dari `violationFeeRupiah`), tidak tergantung tier, travel vs barang, atau jumlah penumpang.
- Dibayar **bersama** kontribusi (Google Play) sesuai alur aplikasi.

## 5. Risiko data (CS)

- Jika **provinsi** tidak terbaca dari geocoding, tier bisa memakai **default** — nominal bisa tidak sesuai ekspektasi user. Tindak: cek koordinat & order di Firestore, arahkan ke tim teknis jika perlu.

## 6. Tampilan driver

- **Dialog “Jenis Harga Kontribusi”** (`showContributionTariffDialog`): penjelasan tier + travel + kargo/dokumen + pelanggaran.
- **Layar Bayar Kontribusi** (`ContributionDriverScreen`): teks UI memakai `TrakaL10n` (Indonesia / Inggris); pesan error di-map ke `contributionError*` / `contributionVerifyFailed`.
- Ringkasan angka mengikuti tarif dari `AppConfigService` (bukan angka statis).
