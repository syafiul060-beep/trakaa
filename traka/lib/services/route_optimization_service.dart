import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/order_model.dart';

/// Greedy route optimization (#7): urutkan stop berdasarkan jarak terdekat.
/// Constraint: pickup harus sebelum dropoff untuk order yang sama.
class RouteOptimizationService {
  RouteOptimizationService._();

  /// Lokasi pickup order (penumpang/pengirim).
  static LatLng? getPickupLocation(OrderModel order) {
    final lat = order.passengerLat ?? order.originLat;
    final lng = order.passengerLng ?? order.originLng;
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  /// Lokasi dropoff order (tujuan penumpang/penerima).
  static LatLng? getDropoffLocation(OrderModel order) {
    if (order.isKirimBarang) {
      final lat = order.receiverLat ?? order.destLat;
      final lng = order.receiverLng ?? order.destLng;
      if (lat == null || lng == null) return null;
      return LatLng(lat, lng);
    }
    if (order.destLat == null || order.destLng == null) return null;
    return LatLng(order.destLat!, order.destLng!);
  }

  /// Jarak antara dua titik (meter).
  static double _distanceM(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
      a.latitude, a.longitude,
      b.latitude, b.longitude,
    );
  }

  /// Load (slot) per order untuk validasi kapasitas (Tahap 3).
  /// Travel: 1 + jumlahKerabat. Kirim barang dokumen: 0. Kargo: [kargoSlotPerOrder].
  static int getOrderLoad(OrderModel order, double kargoSlotPerOrder) {
    if (order.isTravel) {
      final jk = order.jumlahKerabat ?? 0;
      return (jk <= 0) ? 1 : (1 + jk);
    }
    if (order.isKirimBarang) {
      if (order.barangCategory == OrderModel.barangCategoryDokumen) return 0;
      return (kargoSlotPerOrder.ceil()).clamp(1, 10);
    }
    return 1;
  }

  /// Greedy: urutkan stop berdasarkan jarak terdekat dari posisi saat ini.
  /// Setiap langkah: pilih stop terdekat (pickup atau dropoff), update posisi, ulangi.
  /// [maxCapacity] [kargoSlotPerOrder]: validasi kapasitas (Tahap 3). Null = skip.
  /// Returns [(order, isPickup), ...] dalam urutan kunjungan optimal.
  static List<({OrderModel order, bool isPickup})> optimizeStops(
    LatLng driverPosition,
    List<OrderModel> pickupOrders,
    List<OrderModel> dropoffOrders, {
    int? maxCapacity,
    double kargoSlotPerOrder = 1.0,
  }) {
    final result = <({OrderModel order, bool isPickup})>[];
    var remainingPickups = pickupOrders.toList();
    var remainingDropoffs = dropoffOrders.toList();
    var current = driverPosition;
    var currentLoad = 0;

    while (remainingPickups.isNotEmpty || remainingDropoffs.isNotEmpty) {
      OrderModel? best;
      var bestDist = double.infinity;
      var bestIsPickup = false;

      for (final o in remainingPickups) {
        final loc = getPickupLocation(o);
        if (loc == null) continue;
        if (maxCapacity != null) {
          final load = getOrderLoad(o, kargoSlotPerOrder);
          if (currentLoad + load > maxCapacity) continue;
        }
        final d = _distanceM(current, loc);
        if (d < bestDist) {
          bestDist = d;
          best = o;
          bestIsPickup = true;
        }
      }
      for (final o in remainingDropoffs) {
        final loc = getDropoffLocation(o);
        if (loc == null) continue;
        final d = _distanceM(current, loc);
        if (d < bestDist) {
          bestDist = d;
          best = o;
          bestIsPickup = false;
        }
      }

      if (best == null) break;

      if (bestIsPickup) {
        currentLoad += getOrderLoad(best, kargoSlotPerOrder);
      } else {
        currentLoad -= getOrderLoad(best, kargoSlotPerOrder);
        if (currentLoad < 0) currentLoad = 0;
      }

      result.add((order: best, isPickup: bestIsPickup));

      if (bestIsPickup) {
        remainingPickups.remove(best);
        final loc = getPickupLocation(best);
        if (loc != null) current = loc;
      } else {
        remainingDropoffs.remove(best);
        final loc = getDropoffLocation(best);
        if (loc != null) current = loc;
      }
    }

    return result;
  }

  /// Stop berikutnya dari daftar yang sudah di-optimize (untuk navigasi).
  /// Returns null jika list kosong.
  static ({OrderModel order, bool isPickup})? getNextStop(
    LatLng driverPosition,
    List<OrderModel> pickupOrders,
    List<OrderModel> dropoffOrders,
  ) {
    final optimized = optimizeStops(driverPosition, pickupOrders, dropoffOrders);
    return optimized.isEmpty ? null : optimized.first;
  }

  /// #8 Insert optimization: saat order baru masuk ke route yang sudah ada,
  /// cari posisi insert terbaik (pickup + dropoff) dengan cost terkecil.
  /// Constraint: pickup harus sebelum dropoff untuk order yang sama.
  /// [maxCapacity] [kargoSlotPerOrder]: validasi kapasitas (Tahap 3). Null = skip.
  /// Returns route baru dengan order dimasukkan di posisi optimal, atau null jika invalid.
  static List<({OrderModel order, bool isPickup})>? insertOrderOptimal(
    LatLng driverPosition,
    List<({OrderModel order, bool isPickup})> existingRoute,
    OrderModel newOrder, {
    int? maxCapacity,
    double kargoSlotPerOrder = 1.0,
  }) {
    final pickupLoc = getPickupLocation(newOrder);
    final dropoffLoc = getDropoffLocation(newOrder);
    if (pickupLoc == null || dropoffLoc == null) return null;

    final newOrderLoad = getOrderLoad(newOrder, kargoSlotPerOrder);
    List<({OrderModel order, bool isPickup})>? bestRoute;
    var bestCost = double.infinity;

    final n = existingRoute.length;
    for (var i = 0; i <= n; i++) {
      for (var j = i + 1; j <= n + 1; j++) {
        final candidate = _buildInsertedRoute(
          existingRoute,
          newOrder,
          i,
          j,
        );
        if (maxCapacity != null &&
            !_routeRespectsCapacity(
              candidate,
              newOrder,
              newOrderLoad,
              maxCapacity,
              kargoSlotPerOrder,
            )) {
          continue;
        }
        final cost = _routeCost(driverPosition, candidate);
        if (cost < bestCost) {
          bestCost = cost;
          bestRoute = candidate;
        }
      }
    }

    return bestRoute;
  }

  static List<({OrderModel order, bool isPickup})> _buildInsertedRoute(
    List<({OrderModel order, bool isPickup})> route,
    OrderModel newOrder,
    int pickupIdx,
    int dropoffIdx,
  ) {
    final result = <({OrderModel order, bool isPickup})>[];
    final n = route.length;
    final maxK = (n > dropoffIdx ? n : dropoffIdx);
    for (var k = 0; k <= maxK; k++) {
      if (k == pickupIdx) result.add((order: newOrder, isPickup: true));
      if (k == dropoffIdx) result.add((order: newOrder, isPickup: false));
      if (k < n) result.add(route[k]);
    }
    return result;
  }

  static bool _routeRespectsCapacity(
    List<({OrderModel order, bool isPickup})> route,
    OrderModel newOrder,
    int newOrderLoad,
    int maxCapacity,
    double kargoSlotPerOrder,
  ) {
    var load = 0;
    for (final s in route) {
      if (s.order.id == newOrder.id) {
        if (s.isPickup) {
          load += newOrderLoad;
          if (load > maxCapacity) return false;
        } else {
          load -= newOrderLoad;
          if (load < 0) load = 0;
        }
      } else {
        final l = getOrderLoad(s.order, kargoSlotPerOrder);
        if (s.isPickup) {
          load += l;
          if (load > maxCapacity) return false;
        } else {
          load -= l;
          if (load < 0) load = 0;
        }
      }
    }
    return true;
  }

  static double _routeCost(
    LatLng start,
    List<({OrderModel order, bool isPickup})> route,
  ) {
    if (route.isEmpty) return 0;
    var total = 0.0;
    var current = start;
    for (final s in route) {
      final loc = s.isPickup ? getPickupLocation(s.order) : getDropoffLocation(s.order);
      if (loc != null) {
        total += _distanceM(current, loc);
        current = loc;
      }
    }
    return total;
  }
}
