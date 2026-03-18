import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Cek apakah nomor plat kendaraan sudah dipakai driver lain.
class VehiclePlatService {
  VehiclePlatService._();

  /// Cek apakah plat sudah ada di users (milik driver lain).
  /// Return true jika plat dipakai driver lain, false jika tersedia.
  static Future<bool> platExistsForOtherDriver(String plat) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final platUpper = plat.trim().toUpperCase();
      if (platUpper.isEmpty) return false;

      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('vehiclePlat', isEqualTo: platUpper)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) return false;
      final doc = querySnapshot.docs.first;
      return doc.id != user.uid;
    } catch (_) {
      return false;
    }
  }
}
