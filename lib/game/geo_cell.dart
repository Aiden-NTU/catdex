import 'dart:math' as math;

import 'package:h3_core/h3_core.dart' as h3;

/// Canonical H3 gameplay cells.
class GeoCell {
  /// Resolution 9 has an average edge of roughly 200m: a cell and its
  /// immediate ring cover a walkable neighborhood without spanning a town.
  static const int resolution = 9;

  static String fromLatLng(double lat, double lng) =>
      h3.latLngToCell(h3.LatLng(lat, lng), resolution).toHex();

  static List<(double, double)> boundary(String cellId) => h3
      .cellToBoundary(h3.H3Index.parse(cellId))
      .vertices
      .map((point) => (point.lat, point.lng))
      .toList(growable: false);

  static (double, double) center(String cellId) {
    final point = h3.cellToLatLng(h3.H3Index.parse(cellId));
    return (point.lat, point.lng);
  }

  /// The source cell and its six immediate H3 neighbors.
  static List<String> neighborhood(String cellId) => h3
      .gridDisk(h3.H3Index.parse(cellId), 1)
      .map((cell) => cell.toHex())
      .toList(growable: false);

  static double haversineM(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final p1 = lat1 * math.pi / 180;
    final p2 = lat2 * math.pi / 180;
    final dp = (lat2 - lat1) * math.pi / 180;
    final dl = (lng2 - lng1) * math.pi / 180;
    final a =
        math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
