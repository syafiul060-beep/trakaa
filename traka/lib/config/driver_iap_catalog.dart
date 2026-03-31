/// SKU Google Play untuk kontribusi driver (`traka_driver_dues_*`).
/// Dipakai juga sebagai daftar snap tarif navigasi premium agar satu set SKU.
const List<String> kDriverDuesProductIds = [
  'traka_driver_dues_5000',
  'traka_driver_dues_7500',
  'traka_driver_dues_10000',
  'traka_driver_dues_12500',
  'traka_driver_dues_15000',
  'traka_driver_dues_17500',
  'traka_driver_dues_20000',
  'traka_driver_dues_25000',
  'traka_driver_dues_30000',
  'traka_driver_dues_40000',
  'traka_driver_dues_50000',
  'traka_driver_dues_60000',
  'traka_driver_dues_75000',
  'traka_driver_dues_100000',
  'traka_driver_dues_150000',
  'traka_driver_dues_200000',
];

/// Nominal Rupiah (sama urutan dengan [kDriverDuesProductIds]).
const List<int> kDriverDuesAmounts = [
  5000,
  7500,
  10000,
  12500,
  15000,
  17500,
  20000,
  25000,
  30000,
  40000,
  50000,
  60000,
  75000,
  100000,
  150000,
  200000,
];

/// Pilih product ID untuk total Rupiah (ke atas ke nominal terdekat yang tersedia).
String productIdForTotalRupiah(int totalRupiah) {
  for (var i = 0; i < kDriverDuesAmounts.length; i++) {
    if (kDriverDuesAmounts[i] >= totalRupiah) return kDriverDuesProductIds[i];
  }
  return kDriverDuesProductIds.last;
}

/// Nominal Rupiah dari product ID (mis. traka_driver_dues_10000 → 10000).
int getProductAmountFromId(String productId) {
  final match = RegExp(r'traka_driver_dues_(\d+)').firstMatch(productId);
  if (match != null) return int.tryParse(match.group(1) ?? '0') ?? 0;
  return 0;
}
