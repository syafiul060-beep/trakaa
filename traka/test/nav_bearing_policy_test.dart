import 'package:flutter_test/flutter_test.dart';
import 'package:traka/config/marker_assets.dart';

/// Smoke untuk konfig yang menggerakkan ikon chase (tier kecepatan / idle vs panah).
/// Logika utama tetap di `driver_screen.dart` — ubah angka di sini bila sengaja mengubah policy.
void main() {
  group('Nav bearing / chase marker policy', () {
    test('MarkerAssets.speedTier: di bawah idleMax = tier 0', () {
      expect(MarkerAssets.idleMaxKmh, 2.0);
      expect(MarkerAssets.speedTier(0), 0);
      expect(MarkerAssets.speedTier(1.9), 0);
    });

    test('MarkerAssets.speedTier: di atas idleMax = tier bergerak (2)', () {
      expect(MarkerAssets.speedTier(2.0), 2);
      expect(MarkerAssets.speedTier(15), 2);
    });
  });
}
