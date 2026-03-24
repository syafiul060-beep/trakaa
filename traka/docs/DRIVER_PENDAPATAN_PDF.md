# Laporan pendapatan driver → PDF

## Yang sudah ada di app

- **Layar:** `DriverEarningsScreen` — pilih bulan/tahun, ringkasan, tombol **Laporan PDF**.
- **Generate:** `DriverEarningsPdfService` (Syncfusion PDF) — logo, header, tabel pendapatan (termasuk **Jenis**: Travel / Kirim Barang), potongan, ringkasan bersih, blok verifikasi + cap.
- **Footer:** setiap halaman berisi *Halaman x / y* (setelah konten selesai digambar).
- **Setelah PDF jadi:** bottom sheet — **Lihat PDF** (`OpenFilex` / viewer sistem) atau **Bagikan** (`SharePlus.instance.share` + `ShareParams`).

## Saran tampilan PDF (produk)

| Saran | Keterangan |
|--------|------------|
| **Kolom ringkas** | Kolom *Jenis* membedakan travel vs kirim barang tanpa memanjangkan baris dengan rute penuh. |
| **Aksen merek** | Strip biru di atas halaman pertama menyelaraskan dengan identitas Traka. |
| **Font Courier** | Sengaja “mesin ketik” agar terbaca jelas saat dicetak / difax; alternatif: Helvetica jika ingin tampilan lebih “korporat”. |
| **Nomor halaman** | Untuk laporan banyak halaman, bisa ditambah footer *Halaman x / y* (perlu iterasi halaman setelah `grid.draw`). |
| **Watermark** | Opsional *SALINAN* diagonal untuk PDF yang dibagikan (bukan untuk arsip internal). |

## Saran di luar PDF

| Saran | Keterangan |
|--------|------------|
| **Pratinjau** | Bottom sheet setelah generate: **Lihat PDF** memakai `open_filex`. |
| **Ekspor CSV** | Untuk driver yang mengolah data di spreadsheet. |
| **Ringkasan di UI** | Samakan istilah dengan PDF: kotor, potongan, bersih — sudah ditekankan di layar jika konsisten. |

## Dimensi kontribusi (referensi)

Lihat `docs/KONTRIBUSI_DRIVER_DIMENSI.md` (tier rute, travel vs barang, pelanggaran).

## File terkait

- `lib/services/driver_earnings_pdf_service.dart`
- `lib/services/driver_earnings_service.dart` — `DriverEarningsOrderItem.typeLabel`
- `lib/screens/driver_earnings_screen.dart`
