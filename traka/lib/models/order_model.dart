import 'package:cloud_firestore/cloud_firestore.dart';

/// Model pesanan (order) penumpang–driver.
/// Nomor pesanan dibuat otomatis ketika driver dan penumpang sama-sama klik kesepakatan.
class OrderModel {
  final String id;
  final String? orderNumber;
  final String passengerUid;
  final String driverUid;
  final String routeJourneyNumber;
  final String passengerName;
  final String? passengerPhotoUrl;

  /// Bahasa aplikasi penumpang: 'id' | 'en'. EN = turis, driver tampilkan badge.
  final String? passengerAppLocale;
  final String originText;
  final String destText;
  final double? originLat;
  final double? originLng;
  final double? destLat;
  final double? destLng;
  final double? passengerLat;
  final double? passengerLng;
  final String? passengerLocationText;
  final String status;
  final bool driverAgreed;
  final bool passengerAgreed;

  /// Apakah driver sudah klik batalkan.
  final bool driverCancelled;

  /// Apakah penumpang sudah klik batalkan.
  final bool passengerCancelled;

  /// Apakah admin membatalkan pesanan.
  final bool adminCancelled;

  /// Waktu admin membatalkan.
  final DateTime? adminCancelledAt;

  /// Alasan admin membatalkan (untuk audit).
  final String? adminCancelReason;

  /// travel = penumpang sendiri/kerabat; kirim_barang = kirim barang (ada penerima).
  final String orderType;

  /// Kategori barang: 'dokumen' | 'kargo'. Untuk kirim_barang.
  final String? barangCategory;

  /// Nama/jenis barang (untuk kargo).
  final String? barangNama;

  /// Berat barang (kg). Untuk kargo.
  final double? barangBeratKg;

  /// Panjang barang (cm). Untuk kargo.
  final double? barangPanjangCm;

  /// Lebar barang (cm). Untuk kargo.
  final double? barangLebarCm;

  /// Tinggi barang (cm). Untuk kargo.
  final double? barangTinggiCm;

  /// URL foto barang (untuk kargo, opsional). Disimpan di Firebase Storage.
  final String? barangFotoUrl;

  /// UID penerima barang (untuk kirim_barang). Bisa sama dengan passengerUid atau beda.
  final String? receiverUid;

  /// Nama dan foto penerima (untuk kirim_barang, tampilan).
  final String? receiverName;
  final String? receiverPhotoUrl;

  /// Waktu penerima setuju jadi penerima (order lalu ke driver).
  final DateTime? receiverAgreedAt;

  /// Lokasi penerima (untuk antar barang).
  final double? receiverLat;
  final double? receiverLng;
  final String? receiverLocationText;

  /// Waktu penerima scan barcode driver (barang diterima).
  final DateTime? receiverScannedAt;

  /// Jumlah kerabat (untuk travel dengan kerabat). Null = pesan sendiri.
  final int? jumlahKerabat;

  /// Harga yang diusulkan driver (Rupiah). Diset saat driver klik Kesepakatan dan kirim.
  final double? agreedPrice;

  /// Waktu driver mengirim harga kesepakatan.
  final DateTime? agreedPriceAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Waktu pesanan selesai (status completed). Untuk auto-hapus chat 24 jam kemudian.
  final DateTime? completedAt;

  /// Waktu pesan terakhir (di-set Cloud Function saat ada pesan baru).
  final DateTime? lastMessageAt;

  /// UID pengirim pesan terakhir (untuk badge unread driver).
  final String? lastMessageSenderUid;

  /// Teks pesan terakhir (potongan, untuk notifikasi).
  final String? lastMessageText;

  /// Waktu terakhir driver membuka chat untuk order ini (untuk hitung unread).
  final DateTime? driverLastReadAt;

  /// Chat disembunyikan dari list Pesan oleh penumpang (riwayat tetap tampil).
  final bool chatHiddenByPassenger;

  /// Chat disembunyikan dari list Pesan oleh driver (riwayat tetap tampil).
  final bool chatHiddenByDriver;

  /// Chat disembunyikan dari list Pesan oleh penerima (kirim barang). Riwayat tetap tampil.
  final bool chatHiddenByReceiver;

  /// Waktu terakhir penumpang membuka chat (untuk hitung unread). Di-set saat sembunyikan.
  final DateTime? passengerLastReadAt;

  /// Waktu terakhir penerima (receiver) membuka chat. Untuk kirim barang.
  final DateTime? receiverLastReadAt;

  /// Payload barcode penumpang (untuk di-scan driver). DEPRECATED: tidak dipakai lagi; penumpang yang scan.
  final String? passengerBarcodePayload;

  /// Payload barcode driver fase PICKUP (untuk di-scan penumpang saat penjemputan). Di-set saat penumpang setuju.
  final String? driverBarcodePickupPayload;

  /// Payload barcode driver fase COMPLETE (untuk di-scan penumpang saat selesai). Di-set setelah penumpang scan PICKUP.
  final String? driverBarcodePayload;

  /// Waktu driver berhasil scan barcode penumpang. DEPRECATED: tidak dipakai lagi.
  final DateTime? driverScannedAt;

  /// Waktu penumpang/pengirim berhasil scan barcode driver PICKUP (penjemputan terkonfirmasi).
  final DateTime? passengerScannedPickupAt;

  /// Level validasi lokasi untuk scan selesai: 'desa' | 'kecamatan' | 'kabupaten' | 'provinsi'. Default kecamatan.
  /// Penumpang cukup di wilayah admin yang sama, tidak harus di titik tepat tujuan.
  final String? destinationValidationLevel;

  /// Titik jemput penumpang (lokasi saat scan barcode PICKUP). Untuk hitung jarak perjalanan.
  final double? pickupLat;
  final double? pickupLng;

  /// Waktu penumpang berhasil scan barcode driver (perjalanan selesai).
  final DateTime? passengerScannedAt;

  /// Titik turun penumpang (saat penumpang scan barcode driver). Untuk hitung jarak.
  final double? dropLat;
  final double? dropLng;

  /// Jarak perjalanan (km): dari titik jemput sampai titik turun.
  final double? tripDistanceKm;

  /// Jarak naik kapal laut (km) yang dikurangi dari tripDistanceKm untuk hitung tarif.
  final double? ferryDistanceKm;

  /// Tarif perjalanan (Rupiah): jarak × tarif per km (70–85 Rp/km, bisa diubah di admin).
  final double? tripFareRupiah;

  /// Kontribusi kirim barang (Rupiah): jarak × tarif per km tier provinsi (15/35/50).
  final double? tripBarangFareRupiah;

  /// Kontribusi travel (Rupiah): max(jarak × tarif tier, min). Untuk order travel selesai.
  final double? tripTravelContributionRupiah;

  /// ID jadwal driver (pesanan terjadwal dari Pesan nanti). Format: driverUid_yMd_departureMs.
  final String? scheduleId;

  /// Tanggal jadwal (y-m-d) untuk pesanan terjadwal.
  final String? scheduledDate;

  /// Waktu driver sampai di titik penjemputan (dalam radius 300 m). Untuk notifikasi penumpang dan auto-confirm 5 menit.
  final DateTime? driverArrivedAtPickupAt;

  /// Waktu driver mulai navigasi ke penumpang (klik "Ya, arahkan"). Penumpang mulai stream lokasi live.
  final DateTime? driverNavigatingToPickupAt;

  /// Lokasi penumpang live saat driver navigate (di-update penumpang).
  final double? passengerLiveLat;
  final double? passengerLiveLng;
  final DateTime? passengerLiveUpdatedAt;

  /// Waktu penumpang bayar Lacak Driver (Rp 3000) untuk order ini.
  final DateTime? passengerTrackDriverPaidAt;

  /// Nominal IAP lacak barang (Rp) dihitung saat create order; dipakai backend untuk cocokkan SKU.
  final int? lacakBarangIapFeeRupiah;

  /// Waktu pengirim bayar Lacak Barang (kirim barang).
  final DateTime? passengerLacakBarangPaidAt;

  /// Waktu penerima bayar Lacak Barang (kirim barang).
  final DateTime? receiverLacakBarangPaidAt;

  /// Konfirmasi penjemputan tanpa scan barcode (driver klik konfirmasi otomatis).
  final bool autoConfirmPickup;

  /// Konfirmasi selesai tanpa scan barcode (penumpang klik konfirmasi otomatis).
  final bool autoConfirmComplete;

  /// Biaya pelanggaran penumpang (Rp) karena tidak scan barcode saat sampai tujuan.
  final double? passengerViolationFee;

  /// Biaya pelanggaran driver (Rp) karena tidak scan barcode saat jemput penumpang.
  final double? driverViolationFee;

  /// Rating penumpang untuk driver (1-5) setelah perjalanan selesai.
  final int? passengerRating;

  /// Review/ulasan penumpang untuk driver.
  final String? passengerReview;

  /// Waktu penumpang memberi rating.
  final DateTime? passengerRatedAt;

  /// cash | bank | ewallet | qris — instruksi bayar ke driver (bukan escrow).
  final String? passengerPayMethod;
  final String? passengerPayMethodId;
  final DateTime? passengerPayDisclaimerAt;
  final DateTime? passengerPayMarkedAt;

  /// Kirim barang: `sender` | `receiver` — siapa yang lewat hybrid bayar ongkos ke driver. Default pengirim.
  final String? travelFarePaidBy;

  /// Instruksi bayar ke driver untuk penerima (mirror [passengerPay*]) jika [travelFarePaidBy] == receiver.
  final String? receiverPayMethod;
  final String? receiverPayMethodId;
  final DateTime? receiverPayDisclaimerAt;
  final DateTime? receiverPayMarkedAt;

  const OrderModel({
    required this.id,
    this.orderNumber,
    required this.passengerUid,
    required this.driverUid,
    required this.routeJourneyNumber,
    required this.passengerName,
    this.passengerPhotoUrl,
    this.passengerAppLocale,
    required this.originText,
    required this.destText,
    this.originLat,
    this.originLng,
    this.destLat,
    this.destLng,
    this.passengerLat,
    this.passengerLng,
    this.passengerLocationText,
    required this.status,
    required this.driverAgreed,
    required this.passengerAgreed,
    this.driverCancelled = false,
    this.passengerCancelled = false,
    this.adminCancelled = false,
    this.adminCancelledAt,
    this.adminCancelReason,
    this.orderType = 'travel',
    this.barangCategory,
    this.barangNama,
    this.barangBeratKg,
    this.barangPanjangCm,
    this.barangLebarCm,
    this.barangTinggiCm,
    this.barangFotoUrl,
    this.receiverUid,
    this.receiverName,
    this.receiverPhotoUrl,
    this.receiverAgreedAt,
    this.receiverLat,
    this.receiverLng,
    this.receiverLocationText,
    this.receiverScannedAt,
    this.jumlahKerabat,
    this.agreedPrice,
    this.agreedPriceAt,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.lastMessageAt,
    this.lastMessageSenderUid,
    this.lastMessageText,
    this.driverLastReadAt,
    this.chatHiddenByPassenger = false,
    this.chatHiddenByDriver = false,
    this.chatHiddenByReceiver = false,
    this.passengerLastReadAt,
    this.receiverLastReadAt,
    this.passengerBarcodePayload,
    this.driverBarcodePickupPayload,
    this.driverBarcodePayload,
    this.driverScannedAt,
    this.passengerScannedPickupAt,
    this.destinationValidationLevel,
    this.pickupLat,
    this.pickupLng,
    this.passengerScannedAt,
    this.dropLat,
    this.dropLng,
    this.tripDistanceKm,
    this.ferryDistanceKm,
    this.tripFareRupiah,
    this.tripBarangFareRupiah,
    this.tripTravelContributionRupiah,
    this.scheduleId,
    this.scheduledDate,
    this.driverArrivedAtPickupAt,
    this.driverNavigatingToPickupAt,
    this.passengerLiveLat,
    this.passengerLiveLng,
    this.passengerLiveUpdatedAt,
    this.passengerTrackDriverPaidAt,
    this.lacakBarangIapFeeRupiah,
    this.passengerLacakBarangPaidAt,
    this.receiverLacakBarangPaidAt,
    this.autoConfirmPickup = false,
    this.autoConfirmComplete = false,
    this.passengerViolationFee,
    this.driverViolationFee,
    this.passengerRating,
    this.passengerReview,
    this.passengerRatedAt,
    this.passengerPayMethod,
    this.passengerPayMethodId,
    this.passengerPayDisclaimerAt,
    this.passengerPayMarkedAt,
    this.travelFarePaidBy,
    this.receiverPayMethod,
    this.receiverPayMethodId,
    this.receiverPayDisclaimerAt,
    this.receiverPayMarkedAt,
  });

  factory OrderModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return OrderModel(
      id: doc.id,
      orderNumber: d['orderNumber'] as String?,
      passengerUid: (d['passengerUid'] as String?) ?? '',
      driverUid: (d['driverUid'] as String?) ?? '',
      routeJourneyNumber: (d['routeJourneyNumber'] as String?) ?? '',
      passengerName: (d['passengerName'] as String?) ?? '',
      passengerPhotoUrl: d['passengerPhotoUrl'] as String?,
      passengerAppLocale: d['passengerAppLocale'] as String?,
      originText: (d['originText'] as String?) ?? '',
      destText: (d['destText'] as String?) ?? '',
      originLat: (d['originLat'] as num?)?.toDouble(),
      originLng: (d['originLng'] as num?)?.toDouble(),
      destLat: (d['destLat'] as num?)?.toDouble(),
      destLng: (d['destLng'] as num?)?.toDouble(),
      passengerLat: (d['passengerLat'] as num?)?.toDouble(),
      passengerLng: (d['passengerLng'] as num?)?.toDouble(),
      passengerLocationText: d['passengerLocationText'] as String?,
      status: (d['status'] as String?) ?? 'pending_agreement',
      driverAgreed: (d['driverAgreed'] as bool?) ?? false,
      passengerAgreed: (d['passengerAgreed'] as bool?) ?? false,
      driverCancelled: (d['driverCancelled'] as bool?) ?? false,
      passengerCancelled: (d['passengerCancelled'] as bool?) ?? false,
      adminCancelled: (d['adminCancelled'] as bool?) ?? false,
      adminCancelledAt: (d['adminCancelledAt'] as Timestamp?)?.toDate(),
      adminCancelReason: d['adminCancelReason'] as String?,
      orderType: (d['orderType'] as String?) ?? 'travel',
      barangCategory: d['barangCategory'] as String?,
      barangNama: d['barangNama'] as String?,
      barangBeratKg: (d['barangBeratKg'] as num?)?.toDouble(),
      barangPanjangCm: (d['barangPanjangCm'] as num?)?.toDouble(),
      barangLebarCm: (d['barangLebarCm'] as num?)?.toDouble(),
      barangTinggiCm: (d['barangTinggiCm'] as num?)?.toDouble(),
      barangFotoUrl: d['barangFotoUrl'] as String?,
      receiverUid: d['receiverUid'] as String?,
      receiverName: d['receiverName'] as String?,
      receiverPhotoUrl: d['receiverPhotoUrl'] as String?,
      receiverAgreedAt: (d['receiverAgreedAt'] as Timestamp?)?.toDate(),
      receiverLat: (d['receiverLat'] as num?)?.toDouble(),
      receiverLng: (d['receiverLng'] as num?)?.toDouble(),
      receiverLocationText: d['receiverLocationText'] as String?,
      receiverScannedAt: (d['receiverScannedAt'] as Timestamp?)?.toDate(),
      jumlahKerabat: (d['jumlahKerabat'] as num?)?.toInt(),
      agreedPrice: (d['agreedPrice'] as num?)?.toDouble(),
      agreedPriceAt: (d['agreedPriceAt'] as Timestamp?)?.toDate(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
      lastMessageAt: (d['lastMessageAt'] as Timestamp?)?.toDate(),
      lastMessageSenderUid: d['lastMessageSenderUid'] as String?,
      lastMessageText: d['lastMessageText'] as String?,
      driverLastReadAt: (d['driverLastReadAt'] as Timestamp?)?.toDate(),
      chatHiddenByPassenger: (d['chatHiddenByPassenger'] as bool?) ?? false,
      chatHiddenByDriver: (d['chatHiddenByDriver'] as bool?) ?? false,
      chatHiddenByReceiver: (d['chatHiddenByReceiver'] as bool?) ?? false,
      passengerLastReadAt: (d['passengerLastReadAt'] as Timestamp?)?.toDate(),
      receiverLastReadAt: (d['receiverLastReadAt'] as Timestamp?)?.toDate(),
      passengerBarcodePayload: d['passengerBarcodePayload'] as String?,
      driverBarcodePickupPayload: d['driverBarcodePickupPayload'] as String?,
      driverBarcodePayload: d['driverBarcodePayload'] as String?,
      driverScannedAt: (d['driverScannedAt'] as Timestamp?)?.toDate(),
      passengerScannedPickupAt: (d['passengerScannedPickupAt'] as Timestamp?)?.toDate(),
      destinationValidationLevel: d['destinationValidationLevel'] as String?,
      pickupLat: (d['pickupLat'] as num?)?.toDouble(),
      pickupLng: (d['pickupLng'] as num?)?.toDouble(),
      passengerScannedAt: (d['passengerScannedAt'] as Timestamp?)?.toDate(),
      dropLat: (d['dropLat'] as num?)?.toDouble(),
      dropLng: (d['dropLng'] as num?)?.toDouble(),
      tripDistanceKm: (d['tripDistanceKm'] as num?)?.toDouble(),
      ferryDistanceKm: (d['ferryDistanceKm'] as num?)?.toDouble(),
      tripFareRupiah: (d['tripFareRupiah'] as num?)?.toDouble(),
      tripBarangFareRupiah: (d['tripBarangFareRupiah'] as num?)?.toDouble(),
      tripTravelContributionRupiah: (d['tripTravelContributionRupiah'] as num?)?.toDouble(),
      scheduleId: d['scheduleId'] as String?,
      scheduledDate: d['scheduledDate'] as String?,
      driverArrivedAtPickupAt: (d['driverArrivedAtPickupAt'] as Timestamp?)?.toDate(),
      driverNavigatingToPickupAt: (d['driverNavigatingToPickupAt'] as Timestamp?)?.toDate(),
      passengerLiveLat: (d['passengerLiveLat'] as num?)?.toDouble(),
      passengerLiveLng: (d['passengerLiveLng'] as num?)?.toDouble(),
      passengerLiveUpdatedAt: (d['passengerLiveUpdatedAt'] as Timestamp?)?.toDate(),
      passengerTrackDriverPaidAt: (d['passengerTrackDriverPaidAt'] as Timestamp?)?.toDate(),
      lacakBarangIapFeeRupiah: (d['lacakBarangIapFeeRupiah'] as num?)?.toInt(),
      passengerLacakBarangPaidAt: (d['passengerLacakBarangPaidAt'] as Timestamp?)?.toDate(),
      receiverLacakBarangPaidAt: (d['receiverLacakBarangPaidAt'] as Timestamp?)?.toDate(),
      autoConfirmPickup: (d['autoConfirmPickup'] as bool?) ?? false,
      autoConfirmComplete: (d['autoConfirmComplete'] as bool?) ?? false,
      passengerViolationFee: (d['passengerViolationFee'] as num?)?.toDouble(),
      driverViolationFee: (d['driverViolationFee'] as num?)?.toDouble(),
      passengerRating: (d['passengerRating'] as num?)?.toInt(),
      passengerReview: d['passengerReview'] as String?,
      passengerRatedAt: (d['passengerRatedAt'] as Timestamp?)?.toDate(),
      passengerPayMethod: d['passengerPayMethod'] as String?,
      passengerPayMethodId: d['passengerPayMethodId'] as String?,
      passengerPayDisclaimerAt:
          (d['passengerPayDisclaimerAt'] as Timestamp?)?.toDate(),
      passengerPayMarkedAt: (d['passengerPayMarkedAt'] as Timestamp?)?.toDate(),
      travelFarePaidBy: d['travelFarePaidBy'] as String?,
      receiverPayMethod: d['receiverPayMethod'] as String?,
      receiverPayMethodId: d['receiverPayMethodId'] as String?,
      receiverPayDisclaimerAt:
          (d['receiverPayDisclaimerAt'] as Timestamp?)?.toDate(),
      receiverPayMarkedAt: (d['receiverPayMarkedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Siap buka scan barcode: tunai (setelah disclaimer) atau non-tunai (setelah tandai sudah bayar).
  bool get passengerPayReadyForScan {
    final m = passengerPayMethod;
    if (m == null || m.isEmpty) return false;
    if (passengerPayDisclaimerAt == null) return false;
    if (m == 'cash') return true;
    if (m == 'bank' || m == 'ewallet' || m == 'qris') {
      return passengerPayMarkedAt != null &&
          passengerPayMethodId != null &&
          passengerPayMethodId!.isNotEmpty;
    }
    return false;
  }

  /// Siap scan selesai (penerima) setelah hybrid, jika ongkos ditanggung penerima.
  bool get receiverPayReadyForScan {
    final m = receiverPayMethod;
    if (m == null || m.isEmpty) return false;
    if (receiverPayDisclaimerAt == null) return false;
    if (m == 'cash') return true;
    if (m == 'bank' || m == 'ewallet' || m == 'qris') {
      return receiverPayMarkedAt != null &&
          receiverPayMethodId != null &&
          receiverPayMethodId!.isNotEmpty;
    }
    return false;
  }

  /// Untuk kirim barang: `sender` atau `receiver`. Order lama / travel: selalu sender.
  String get effectiveTravelFarePaidBy {
    if (!isKirimBarang) return travelFarePaidBySender;
    if (travelFarePaidBy == travelFarePaidByReceiver) {
      return travelFarePaidByReceiver;
    }
    return travelFarePaidBySender;
  }

  /// Hybrid ongkos sebelum scan PICKUP (pengirim): travel selalu ya; kirim barang hanya jika pengirim yang bayar ongkos.
  bool get hybridPayRequiredBeforeSenderScan =>
      !isKirimBarang || effectiveTravelFarePaidBy == travelFarePaidBySender;

  /// Hybrid ongkos sebelum scan COMPLETE (penerima): hanya kirim barang + ongkos penerima.
  bool get hybridPayRequiredBeforeReceiverScan =>
      isKirimBarang && effectiveTravelFarePaidBy == travelFarePaidByReceiver;

  bool get isTravel => orderType == OrderModel.typeTravel;
  bool get isKirimBarang => orderType == OrderModel.typeKirimBarang;

  /// Konstanta jenis pesanan (untuk program/fungsi nanti).
  static const String typeKirimBarang = 'kirim_barang';
  static const String typeTravel = 'travel';

  /// Siapa membayar ongkos travel ke driver (kirim barang).
  static const String travelFarePaidBySender = 'sender';
  static const String travelFarePaidByReceiver = 'receiver';

  /// Apakah pesan travel sendiri (1 orang).
  bool get isTravelSendiri =>
      orderType == typeTravel && (jumlahKerabat == null || jumlahKerabat == 0);

  /// Apakah pesan travel dengan kerabat (2+ orang).
  bool get isTravelKerabat =>
      orderType == typeTravel && jumlahKerabat != null && jumlahKerabat! > 0;

  /// Jumlah total penumpang: 1 jika sendiri, 1 + jumlahKerabat jika dengan kerabat.
  int get totalPenumpang {
    if (orderType != typeTravel) return 0;
    if (jumlahKerabat == null || jumlahKerabat! <= 0) return 1;
    return 1 + jumlahKerabat!;
  }

  /// Kategori barang untuk tampilan: Dokumen / Kargo.
  static const String barangCategoryDokumen = 'dokumen';
  static const String barangCategoryKargo = 'kargo';

  /// Untuk order lama tanpa barangCategory: diperlakukan sebagai Kargo.
  String get barangCategoryDisplayLabel {
    if (barangCategory == barangCategoryDokumen) return 'Dokumen';
    if (barangCategory == barangCategoryKargo) return 'Kargo';
    if (orderType == typeKirimBarang) return 'Kargo'; // Order lama: default Kargo
    return 'Kirim Barang';
  }

  /// Teks detail barang untuk tampilan (kargo: nama, berat, dimensi).
  /// Order lama tanpa barangCategory diperlakukan sebagai kargo (tanpa detail).
  String? get barangDetailDisplay {
    final isKargo = barangCategory == barangCategoryKargo ||
        (orderType == typeKirimBarang && barangCategory == null);
    if (!isKargo) return null;
    final parts = <String>[];
    if (barangNama != null && barangNama!.trim().isNotEmpty) {
      parts.add(barangNama!.trim());
    }
    if (barangBeratKg != null && barangBeratKg! > 0) {
      parts.add('${barangBeratKg!.toStringAsFixed(1)} kg');
    }
    if (barangPanjangCm != null && barangLebarCm != null && barangTinggiCm != null &&
        barangPanjangCm! > 0 && barangLebarCm! > 0 && barangTinggiCm! > 0) {
      parts.add('${barangPanjangCm!.toInt()}×${barangLebarCm!.toInt()}×${barangTinggiCm!.toInt()} cm');
    } else if (barangPanjangCm != null && barangLebarCm != null &&
        barangPanjangCm! > 0 && barangLebarCm! > 0) {
      parts.add('${barangPanjangCm!.toInt()}×${barangLebarCm!.toInt()} cm');
    }
    return parts.isEmpty ? null : parts.join(' • ');
  }

  /// Label untuk tampilan & pesan otomatis di chat (Kirim Barang / Pesan Travel 1 orang / Pesan Travel X orang - dengan kerabat).
  String get orderTypeDisplayLabel {
    if (orderType == typeKirimBarang) {
      if (barangCategory == barangCategoryDokumen) return 'Kirim Barang (Dokumen)';
      if (barangCategory == barangCategoryKargo) return 'Kirim Barang (Kargo)';
      return 'Kirim Barang (Kargo)'; // Order lama tanpa kategori: default Kargo
    }
    if (orderType != typeTravel) return 'Pesan';
    if (jumlahKerabat == null || jumlahKerabat! <= 0) {
      return 'Pesan Travel (1 orang)';
    }
    final total = 1 + jumlahKerabat!;
    return 'Pesan Travel ($total orang - dengan kerabat)';
  }

  /// Buat teks pesan otomatis "Jenis pesanan: ..." untuk dikirim ke chat.
  String get orderTypeAutoMessageText =>
      'Jenis pesanan: $orderTypeDisplayLabel';

  bool get isAgreed => status == 'agreed';
  bool get isPickedUp => status == 'picked_up';
  bool get isCompleted => status == 'completed';
  bool get isPendingAgreement => status == 'pending_agreement';
  /// Kirim barang: menunggu penerima setuju (penerima belum konfirmasi).
  bool get isPendingReceiver => status == 'pending_receiver';
  bool get canDriverAgree => !driverAgreed;
  bool get canPassengerAgree => driverAgreed && !passengerAgreed;
  bool get hasPassengerLocation => passengerLat != null && passengerLng != null;

  /// Titik penumpang untuk jarak driver↔penumpang saat jemput (auto-confirm & validasi server):
  /// utamakan **live** jika masih segar (≤5 menit), lalu `passengerLat`/`Lng`, lalu live tanpa syarat waktu.
  (double, double)? get coordsForDriverPickupProximity {
    final now = DateTime.now();
    if (passengerLiveLat != null &&
        passengerLiveLng != null &&
        passengerLiveUpdatedAt != null) {
      if (now.difference(passengerLiveUpdatedAt!).inSeconds <= 300) {
        return (passengerLiveLat!, passengerLiveLng!);
      }
    }
    if (passengerLat != null && passengerLng != null) {
      return (passengerLat!, passengerLng!);
    }
    if (passengerLiveLat != null && passengerLiveLng != null) {
      return (passengerLiveLat!, passengerLiveLng!);
    }
    return null;
  }

  /// Apakah sudah ada yang klik batalkan (driver, penumpang, atau admin).
  bool get isCancelled =>
      driverCancelled || passengerCancelled || adminCancelled;

  /// Apakah driver sudah klik batalkan.
  bool get isDriverCancelled => driverCancelled;

  /// Apakah penumpang sudah klik batalkan.
  bool get isPassengerCancelled => passengerCancelled;

  /// Apakah admin membatalkan pesanan.
  bool get isAdminCancelled => adminCancelled;
  bool get hasPassengerBarcode =>
      passengerBarcodePayload != null && passengerBarcodePayload!.isNotEmpty;
  /// Barcode driver fase PICKUP (untuk penjemputan). Tersedia saat agreed.
  bool get hasDriverBarcodePickup =>
      driverBarcodePickupPayload != null && driverBarcodePickupPayload!.isNotEmpty;
  /// Barcode driver fase COMPLETE (untuk selesai). Tersedia saat picked_up.
  bool get hasDriverBarcode =>
      driverBarcodePayload != null && driverBarcodePayload!.isNotEmpty;
  /// Order sudah dijemput (driver scan lama ATAU penumpang scan PICKUP).
  bool get hasDriverScannedPassenger => driverScannedAt != null || passengerScannedPickupAt != null;
  /// Penumpang/pengirim sudah scan barcode PICKUP (penjemputan terkonfirmasi).
  bool get hasPassengerScannedPickup => passengerScannedPickupAt != null;
  bool get hasPassengerScannedDriver => passengerScannedAt != null;

  /// Untuk kirim_barang: apakah penerima sudah scan barcode driver (barang diterima).
  bool get hasReceiverScannedDriver => receiverScannedAt != null;

  /// Pesanan dari "Pesan nanti" (terjadwal), bukan driver aktif.
  bool get isScheduledOrder => scheduleId != null && scheduleId!.isNotEmpty;

  /// Penumpang memakai bahasa Inggris (turis). Driver tampilkan badge.
  bool get isPassengerEnglish => passengerAppLocale == 'en';

  /// Ada pesan belum dibaca driver: pesan terakhir dari pihak lain setelah [driverLastReadAt].
  /// Jika [lastMessageSenderUid] null (data lama), tidak dianggap unread — hindari false positive
  /// saat `null != uid` selalu true.
  bool hasUnreadChatForDriver(String driverUid) {
    if (lastMessageAt == null) return false;
    final readAt = driverLastReadAt;
    if (readAt != null && !lastMessageAt!.isAfter(readAt)) return false;
    final sender = lastMessageSenderUid;
    if (sender == null) return false;
    return sender != driverUid;
  }

  /// Unread untuk penumpang/pengirim (bukan penerima).
  bool hasUnreadChatForPassenger(String passengerUid) {
    if (lastMessageAt == null) return false;
    final readAt = passengerLastReadAt;
    if (readAt != null && !lastMessageAt!.isAfter(readAt)) return false;
    final sender = lastMessageSenderUid;
    if (sender == null) return false;
    return sender != passengerUid;
  }

  /// Unread untuk penerima (kirim barang).
  bool hasUnreadChatForReceiver(String receiverUid) {
    if (lastMessageAt == null) return false;
    final readAt = receiverLastReadAt;
    if (readAt != null && !lastMessageAt!.isAfter(readAt)) return false;
    final sender = lastMessageSenderUid;
    if (sender == null) return false;
    return sender != receiverUid;
  }
}
