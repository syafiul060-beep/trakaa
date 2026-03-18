import 'package:google_maps_flutter/google_maps_flutter.dart';

/// State interpolasi per driver (real-time + semut + snap-to-road).
class DriverTrackState {
  LatLng displayed;
  LatLng target;
  DateTime? lastUpdated;
  /// Bearing (derajat) untuk rotasi icon mobil. Asset: depan = selatan, rotation = (bearing + 180) % 360.
  double bearing = 0;
  int interpStartSeg = -1;
  double interpStartRatio = 0;
  int interpEndSeg = -1;
  double interpEndRatio = 0;
  bool usePolyline = false;
  double progress = 0;

  DriverTrackState({
    required this.displayed,
    required this.target,
    this.lastUpdated,
  });
}
