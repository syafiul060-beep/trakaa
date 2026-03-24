# Peta Traka: north-up vs ikut heading (acuan per layar)

Dokumen ini menjawab: **kapan peta sebaiknya utara ke atas (north-up)** vs **ikut arah maju/heading (heading-up)**, mengacu pola umum app ride-hailing (mis. Grab) dan konteks Traka saat ini.

---

## Istilah singkat

| Istilah | Arti |
|--------|------|
| **North-up** | Utara tetap di atas layar; peta tidak berputar mengikuti arah HP. Cocok untuk **mencari**, **membandingkan posisi** beberapa titik. |
| **Heading-up** | Arah yang dianggap “maju” (mis. jalur navigasi) mengarah ke atas layar; peta **berputar**. Cocok untuk **belokan & navigasi**. |

### Kenapa north-up itu saran yang bagus untuk beranda / “cari driver”

North-up **bukan** karena teknisnya lebih mudah saja — ini juga **UX yang masuk akal** di layar seperti beranda Traka:

1. **Orientasi tetap** — User tidak harus memutar kepala mengikuti peta yang ikut berputar; “atas = utara” selalu sama, jadi mudah membandingkan **posisi Anda**, **driver**, dan **tujuan** dalam satu gambar mental.
2. **HP sering digerakkan** — Di jalan, tangan memegang miring atau berubah; kalau peta ikut heading, gambar terus berputar dan bisa membingungkan. North-up **stabil** saat badan/HP tidak menghadap jalan.
3. **Tugasnya “melihat siapa di sekitar”** — Bukan memutuskan belokan per detik. Fokusnya **siapa di mana**, bukan “depan saya belok kanan” — itu tugas lain (navigasi / lacak mendetail).
4. **Selaras pola umum Grab/Gojek** — Di layar utama penumpang, peta sering **north-up**; mode yang lebih “ikut jalan” dipakai saat konteksnya jelas **navigasi** atau mitra mengemudi.

Singkatnya: **north-up = peta yang tenang untuk memilih dan mengamati**; **heading-up = peta yang mengikuti arah maju, cocok saat user benar-benar “mengemudi mengikuti rute”.**

---

## Prinsip umum (seperti pola Grab/Gojek)

1. **Layar “cari / lihat sekitar”** → default **north-up**, agar stabil saat HP diputar.
2. **Layar “navigasi jalan / ikuti rute”** → **heading-up** atau mode campuran + tombol **kompas / reset ke utara**.
3. **Lacak orang/kendaraan** → sering **north-up** + garis/ETA; heading-up opsional jika user eksplisit ingin “mode navigasi”.

**Beranda penumpang:** default **north-up**. Tombol **kompas / navigasi** di samping kontrol satelit & zoom memakai ikon jelajah (`explore_outlined`) / navigasi (`navigation`) — ketuk untuk **ikut bearing GPS** (heading-up); ketuk lagi untuk kembali **utara ke atas**. Saat peta di-zoom agar memuat semua driver hasil cari, mode ikut arah **dimatikan otomatis** agar fokus ke area driver. **Lalu lintas:** layer kemacetan Google (ikon `traffic`) — default **aktif**, bisa dimatikan untuk tampilan lebih bersih / hemat render.

---

## Matriks acuan per layar Traka

| Layar / file | Peran peta | Rekomendasi | Catatan |
|--------------|------------|-------------|---------|
| **Beranda penumpang** (`penumpang_screen.dart`) | Cari driver, marker driver, bounds setelah cari | **North-up default**; **heading-up opsional** (tombol kompas di kontrol peta) | Setelah fit bounds driver, mode ikut arah dimatikan. |
| **Cari travel** (`cari_travel_screen.dart`) | Pilih asal–tujuan di peta | **North-up** | Fokus input lokasi, bukan belokan real-time. |
| **Lacak (widget)** (`passenger_track_map_widget.dart`) | Lacak driver/barang, follow posisi | **Default north-up**; **heading-up opsional** (toggle) jika ada mode “navigasi ke titik” | Jika nanti ditambah navigasi turn-by-turn, pertimbangkan heading-up + kompas. |
| **Driver — beranda / operasional** (`driver_screen.dart`) | Rute kerja, navigasi driver | **Heading-up** umum untuk **mode navigasi**; north-up untuk **overview** | Driver sering butuh belokan jelas — pola ini mirip app mitra. **Geser peta** mematikan ikuti kamera; kamera **ikut lagi otomatis** setelah GPS bergerak cukup jauh (~90 m) dari titik saat geser, atau segera lewat tombol **Fokus**. |
| **Jadwal rute** (`driver_jadwal_rute_screen.dart`) | Pratinjau rute | **North-up** | Baca rute besar, bukan nyetir real-time. |
| **Data order driver** (`data_order_driver_screen.dart`) | Peta konteks order | **North-up** kecuali ada mode “navigasi” eksplisit | Sesuaikan jika satu layar dipakai untuk navigasi penuh. |

---

## Status implementasi

- **Beranda penumpang** (`penumpang_screen.dart` + `MapTypeZoomControls`): toggle north-up ↔ ikut heading + stream lokasi ringan saat mode heading aktif.
- Layar lain: bisa mengikuti pola yang sama bila dibutuhkan.

---

## Gaya peta (bangunan, POI, label)

- **JSON** `assets/map_styles/light_custom.json` & `dark.json`: ikon POI **penuh** (`labels.icon` on), **massa bangunan** (`landscape.man_made`), nama kota (`administrative.locality`), jalan kuning — dibaca bersama `buildingsEnabled` + **indoor** (mal) lewat `indoorViewEnabled` di `GoogleMap`.
- **Toolbar Google** (Android) dimatikan (`mapToolbarEnabled: false`) agar tampilan lebih bersih.

## Tautan terkait

- Peta penumpang & ikon: [`CHECKLIST_ICON_MOBIL_PETA_PENUMPANG.md`](CHECKLIST_ICON_MOBIL_PETA_PENUMPANG.md)
- Uji regresi peta: [`QA_REGRESI_ALUR_UTAMA.md`](QA_REGRESI_ALUR_UTAMA.md) (bagian D)
