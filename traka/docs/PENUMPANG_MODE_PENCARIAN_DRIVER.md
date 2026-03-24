# Penumpang: dua mode pencarian driver

Di beranda penumpang, **mencari driver** bisa berarti dua hal berbeda. Menjelaskan ini ke pengguna (dan dukungan internal) mengurangi salah paham “bug” saat daftar kosong.

**Mode rute (asal + tujuan lengkap)** memakai filter geometri: titik jemput dan antar harus masuk koridor rute alternatif driver (Directions + aturan urutan di kode). Hasilnya adalah driver yang **dianggap searah** dengan perjalanan Anda. Jika tidak ada yang cocok, bukan berarti tidak ada driver *siap kerja* di Firestore/API—hanya tidak ada yang lolos filter rute.

**Mode sekitar (Driver sekitar / fallback)** menampilkan driver aktif dalam radius tetap dari lokasi Anda (mis. 40 km), **tanpa** memastikan rute penumpang mengikuti polyline driver. Cocok untuk menemukan siapa yang sedang beroperasi di sekitar, lalu cek detail rute driver sebelum memesan.

Firebase Analytics mencatat hasil pencarian lewat event `passenger_driver_search_outcome` (nilai `outcome` antara lain: `route_search_empty`, `route_search_directions_all_failed`, `nearby_search_empty`, `nearby_fallback_from_route`).
