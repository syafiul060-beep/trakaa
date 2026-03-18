import 'package:cloud_firestore/cloud_firestore.dart';

/// Service untuk dashboard pendapatan driver.
/// Menghitung total pendapatan dari order completed (agreedPrice/tripBarangFareRupiah),
/// potongan kontribusi, dan pelanggaran.
class DriverEarningsService {
  static const String _collectionOrders = 'orders';
  static const String _collectionContributionPayments = 'contribution_payments';
  static const String _collectionViolationRecords = 'violation_records';
  static const String _collectionUsers = 'users';

  /// Total pendapatan driver dari order completed (agreedPrice).
  static Future<double> getTotalEarnings(String driverUid) async {
    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('driverUid', isEqualTo: driverUid)
        .where('status', isEqualTo: 'completed')
        .get();

    var total = 0.0;
    for (final doc in snap.docs) {
      final price = (doc.data()['agreedPrice'] as num?)?.toDouble();
      if (price != null && price > 0) total += price;
    }
    return total;
  }

  /// Total potongan kontribusi yang sudah dibayar driver (all-time).
  static Future<double> getTotalContributionPaid(String driverUid) async {
    final snap = await FirebaseFirestore.instance
        .collection(_collectionContributionPayments)
        .where('driverUid', isEqualTo: driverUid)
        .get();

    var total = 0.0;
    for (final doc in snap.docs) {
      final amount = (doc.data()['amountRupiah'] as num?)?.toDouble();
      if (amount != null && amount > 0) total += amount;
    }
    return total;
  }

  /// Total pelanggaran yang sudah dibayar driver (all-time).
  static Future<double> getTotalViolationPaid(String driverUid) async {
    final snap = await FirebaseFirestore.instance
        .collection(_collectionViolationRecords)
        .where('userId', isEqualTo: driverUid)
        .where('type', isEqualTo: 'driver')
        .get();

    var total = 0.0;
    for (final doc in snap.docs) {
      final d = doc.data();
      final paidAt = d['paidAt'] as Timestamp?;
      if (paidAt == null) continue;
      final amount = (d['amount'] as num?)?.toDouble() ?? 5000.0;
      total += amount;
    }
    return total;
  }

  /// Jumlah pelanggaran driver (sudah bayar + belum bayar).
  static Future<int> getViolationCount(String driverUid) async {
    final snap = await FirebaseFirestore.instance
        .collection(_collectionViolationRecords)
        .where('userId', isEqualTo: driverUid)
        .where('type', isEqualTo: 'driver')
        .get();
    return snap.docs.length;
  }

  /// Pelanggaran belum dibayar (Rp) dari users/{uid}.
  static Future<double> getOutstandingViolationFee(String driverUid) async {
    final doc = await FirebaseFirestore.instance
        .collection(_collectionUsers)
        .doc(driverUid)
        .get();
    final fee = (doc.data()?['outstandingViolationFee'] as num?)?.toDouble();
    return fee ?? 0.0;
  }

  /// Pendapatan hari ini.
  static Future<double> getTodayEarnings(String driverUid) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('driverUid', isEqualTo: driverUid)
        .where('status', isEqualTo: 'completed')
        .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .get();

    var total = 0.0;
    for (final doc in snap.docs) {
      final completedAt = (doc.data()['completedAt'] as Timestamp?)?.toDate();
      if (completedAt != null && completedAt.isAfter(startOfDay)) {
        final price = (doc.data()['agreedPrice'] as num?)?.toDouble();
        if (price != null && price > 0) total += price;
      }
    }
    return total;
  }

  /// Pendapatan minggu ini (7 hari terakhir).
  static Future<double> getWeekEarnings(String driverUid) async {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));

    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('driverUid', isEqualTo: driverUid)
        .where('status', isEqualTo: 'completed')
        .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(weekAgo))
        .get();

    var total = 0.0;
    for (final doc in snap.docs) {
      final completedAt = (doc.data()['completedAt'] as Timestamp?)?.toDate();
      if (completedAt != null && completedAt.isAfter(weekAgo)) {
        final price = (doc.data()['agreedPrice'] as num?)?.toDouble();
        if (price != null && price > 0) total += price;
      }
    }
    return total;
  }

  /// Jumlah perjalanan selesai.
  static Future<int> getCompletedTripCount(String driverUid) async {
    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('driverUid', isEqualTo: driverUid)
        .where('status', isEqualTo: 'completed')
        .get();
    return snap.docs.length;
  }

  /// Item pendapatan per order (untuk laporan bulanan).
  static Future<List<DriverEarningsOrderItem>> getEarningsByMonth(
    String driverUid,
    int year,
    int month,
  ) async {
    final start = DateTime(year, month, 1);
    final end = month < 12 ? DateTime(year, month + 1, 1) : DateTime(year + 1, 1, 1);

    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('driverUid', isEqualTo: driverUid)
        .where('status', isEqualTo: 'completed')
        .get();

    final items = <DriverEarningsOrderItem>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      final completedAt = (d['completedAt'] as Timestamp?)?.toDate();
      if (completedAt == null || completedAt.isBefore(start) || !completedAt.isBefore(end)) continue;
      final price = (d['agreedPrice'] as num?)?.toDouble();
      if (price == null || price <= 0) continue;
      final orderType = d['orderType'] as String? ?? 'travel';
      final originText = d['originText'] as String? ?? '-';
      final destText = d['destText'] as String? ?? '-';
      final orderNumber = d['orderNumber'] as String? ?? doc.id;
      items.add(DriverEarningsOrderItem(
        orderId: doc.id,
        orderNumber: orderNumber,
        completedAt: completedAt,
        amountRupiah: price,
        orderType: orderType,
        originText: originText,
        destText: destText,
      ));
    }
    items.sort((a, b) => a.completedAt.compareTo(b.completedAt));
    return items;
  }

  /// Item potongan kontribusi per bulan.
  static Future<List<DriverContributionItem>> getContributionsByMonth(
    String driverUid,
    int year,
    int month,
  ) async {
    final start = DateTime(year, month, 1);
    final end = month < 12 ? DateTime(year, month + 1, 1) : DateTime(year + 1, 1, 1);

    final snap = await FirebaseFirestore.instance
        .collection(_collectionContributionPayments)
        .where('driverUid', isEqualTo: driverUid)
        .get();

    final items = <DriverContributionItem>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      final paidAt = (d['paidAt'] as Timestamp?)?.toDate();
      if (paidAt == null || paidAt.isBefore(start) || !paidAt.isBefore(end)) continue;
      final amount = (d['amountRupiah'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) continue;
      items.add(DriverContributionItem(
        paidAt: paidAt,
        amountRupiah: amount,
        orderId: d['orderId'] as String?,
      ));
    }
    items.sort((a, b) => a.paidAt.compareTo(b.paidAt));
    return items;
  }

  /// Item pelanggaran yang dibayar per bulan.
  static Future<List<DriverViolationItem>> getViolationsByMonth(
    String driverUid,
    int year,
    int month,
  ) async {
    final start = DateTime(year, month, 1);
    final end = month < 12 ? DateTime(year, month + 1, 1) : DateTime(year + 1, 1, 1);

    final snap = await FirebaseFirestore.instance
        .collection(_collectionViolationRecords)
        .where('userId', isEqualTo: driverUid)
        .where('type', isEqualTo: 'driver')
        .get();

    final items = <DriverViolationItem>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      final paidAt = (d['paidAt'] as Timestamp?)?.toDate();
      if (paidAt == null || paidAt.isBefore(start) || !paidAt.isBefore(end)) continue;
      final amount = (d['amount'] as num?)?.toDouble() ?? 5000;
      items.add(DriverViolationItem(
        paidAt: paidAt,
        amountRupiah: amount,
        orderId: d['orderId'] as String?,
      ));
    }
    items.sort((a, b) => a.paidAt.compareTo(b.paidAt));
    return items;
  }
}

/// Item order untuk laporan pendapatan.
class DriverEarningsOrderItem {
  final String orderId;
  final String orderNumber;
  final DateTime completedAt;
  final double amountRupiah;
  final String orderType;
  final String originText;
  final String destText;

  DriverEarningsOrderItem({
    required this.orderId,
    required this.orderNumber,
    required this.completedAt,
    required this.amountRupiah,
    required this.orderType,
    required this.originText,
    required this.destText,
  });

  String get typeLabel => orderType == 'kirim_barang' ? 'Kirim Barang' : 'Travel';
  String get routeText => '$originText - $destText';
}

/// Item kontribusi untuk laporan.
class DriverContributionItem {
  final DateTime paidAt;
  final double amountRupiah;
  final String? orderId;

  DriverContributionItem({
    required this.paidAt,
    required this.amountRupiah,
    this.orderId,
  });
}

/// Item pelanggaran untuk laporan.
class DriverViolationItem {
  final DateTime paidAt;
  final double amountRupiah;
  final String? orderId;

  DriverViolationItem({
    required this.paidAt,
    required this.amountRupiah,
    this.orderId,
  });
}
