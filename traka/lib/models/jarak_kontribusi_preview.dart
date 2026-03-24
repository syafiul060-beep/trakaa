/// Hasil hitung jarak/kontribusi untuk teks chat pertama (bukan persist ke Firestore).
class JarakKontribusiPreview {
  const JarakKontribusiPreview({
    required this.kmStraight,
    required this.ferryKm,
    required this.contributionRp,
  });

  /// Jarak garis lurus asal–tujuan (km).
  final double kmStraight;

  /// Estimasi segmen laut yang dikurangi dari tarif (km).
  final double ferryKm;

  /// Estimasi kontribusi driver (Rp), bulat.
  final int contributionRp;
}
