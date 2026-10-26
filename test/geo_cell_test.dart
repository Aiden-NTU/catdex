import 'package:catdex/game/geo_cell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeoCell H3 properties', () {
    test('uses a canonical resolution-9 H3 index', () {
      final cell = GeoCell.fromLatLng(51.5074, -0.1278);
      expect(cell, matches(RegExp(r'^89[0-9a-f]{13}$')));
      expect(GeoCell.fromLatLng(51.5074, -0.1278), cell);
    });

    test('returns a real hexagonal boundary', () {
      final cell = GeoCell.fromLatLng(51.5074, -0.1278);
      final boundary = GeoCell.boundary(cell);
      expect(boundary, hasLength(6));
      expect(boundary.toSet(), hasLength(6));
    });

    test('center maps back to the same cell', () {
      for (final point in [
        (0.0, 0.0),
        (51.5074, -0.1278),
        (-33.8688, 151.2093),
      ]) {
        final cell = GeoCell.fromLatLng(point.$1, point.$2);
        final center = GeoCell.center(cell);
        expect(GeoCell.fromLatLng(center.$1, center.$2), cell);
      }
    });

    test('neighborhood is a unique H3 disk including the source', () {
      final source = GeoCell.fromLatLng(51.5074, -0.1278);
      final cells = GeoCell.neighborhood(source);
      expect(cells, hasLength(7));
      expect(cells.toSet(), hasLength(7));
      expect(cells, contains(source));
    });
  });

  group('haversine distance', () {
    test('is zero for identical points and symmetric', () {
      expect(GeoCell.haversineM(10, 20, 10, 20), closeTo(0, 1e-9));
      final forward = GeoCell.haversineM(51.5074, -0.1278, 48.8566, 2.3522);
      final reverse = GeoCell.haversineM(48.8566, 2.3522, 51.5074, -0.1278);
      expect(forward, closeTo(reverse, 1e-9));
    });

    test('one degree at the equator is approximately 111.2 km', () {
      expect(GeoCell.haversineM(0, 0, 0, 1), closeTo(111195, 100));
    });
  });
}
