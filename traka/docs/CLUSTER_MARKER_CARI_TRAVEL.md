# Cluster Marker di Cari Travel

## Overview

Layar Cari Travel memakai **cluster marker** agar peta tetap rapi saat banyak driver ditampilkan. Marker yang berdekatan digabung menjadi satu cluster dengan angka.

## Package

- `google_maps_cluster_manager_2: ^3.2.0`

## Perilaku

| Kondisi | Tampilan |
|---------|----------|
| **1 driver** | Marker tunggal (warna sesuai kapasitas: hijau/kuning/merah) |
| **Banyak driver berdekatan** | Cluster bundar biru dengan angka |
| **Tap cluster** | Zoom in ke area cluster |
| **Tap marker tunggal** | Buka sheet Pesan Travel |

## Konfigurasi

- `stopClusteringZoom: 16.0` – di zoom 16 ke atas, marker tidak di-cluster
- Icon cluster: lingkaran biru (#2196F3) dengan teks putih

## File

- `lib/screens/cari_travel_screen.dart` – `_DriverClusterItem`, `ClusterManager`, `_buildClusterMarker`
