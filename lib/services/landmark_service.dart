import 'dart:convert';

import 'package:http/http.dart' as http;

/// Nearby real-world places from OpenStreetMap (Overpass), used as automatic
/// Catdex event hubs.
class LandmarkService {
  LandmarkService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, _CacheEntry> _cache = {};

  static const _radiusM = 1400;
  static const _ttl = Duration(minutes: 25);

  Future<List<Landmark>> nearby({
    required double lat,
    required double lng,
    required String cellId,
  }) async {
    final cached = _cache[cellId];
    final now = DateTime.now().toUtc();
    if (cached != null && now.difference(cached.at) < _ttl) {
      return cached.landmarks;
    }

    final query = '''
[out:json][timeout:20];
(
  node["leisure"~"park|playground|garden"](around:$_radiusM,$lat,$lng);
  node["amenity"~"cafe|library|community_centre|arts_centre"](around:$_radiusM,$lat,$lng);
  node["tourism"~"attraction|museum|viewpoint"](around:$_radiusM,$lat,$lng);
  node["shop"="pet"](around:$_radiusM,$lat,$lng);
  way["leisure"~"park|playground|garden"](around:$_radiusM,$lat,$lng);
  way["amenity"~"cafe|library|community_centre"](around:$_radiusM,$lat,$lng);
  way["tourism"~"attraction|museum"](around:$_radiusM,$lat,$lng);
);
out center 48;
''';

    try {
      final response = await _client
          .post(
            Uri.parse('https://overpass-api.de/api/interpreter'),
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded',
              'User-Agent': 'Catdex/1.0 (local play; landmark hubs)',
            },
            body: 'data=${Uri.encodeQueryComponent(query)}',
          )
          .timeout(const Duration(seconds: 22));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return cached?.landmarks ?? const [];
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = decoded['elements'] as List? ?? const [];
      final landmarks = <Landmark>[];
      final seen = <String>{};
      for (final raw in elements) {
        if (raw is! Map) continue;
        final map = raw.cast<String, dynamic>();
        final tags = (map['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
        final name = (tags['name'] as String?)?.trim();
        if (name == null || name.isEmpty) continue;
        final point = _coords(map);
        if (point == null) continue;
        final kind = _kindFor(tags);
        final id = '${map['type']}-${map['id']}';
        if (!seen.add(id)) continue;
        landmarks.add(
          Landmark(
            id: id,
            name: name,
            lat: point.$1,
            lng: point.$2,
            kind: kind,
            osmTags: tags,
          ),
        );
      }
      landmarks.sort((a, b) {
        final da = _approxMeters(lat, lng, a.lat, a.lng);
        final db = _approxMeters(lat, lng, b.lat, b.lng);
        return da.compareTo(db);
      });
      final trimmed = landmarks.take(16).toList(growable: false);
      _cache[cellId] = _CacheEntry(at: now, landmarks: trimmed);
      return trimmed;
    } on Object {
      return cached?.landmarks ?? const [];
    }
  }

  static (double, double)? _coords(Map<String, dynamic> element) {
    final lat = (element['lat'] as num?)?.toDouble();
    final lng = (element['lon'] as num?)?.toDouble();
    if (lat != null && lng != null) return (lat, lng);
    final center = element['center'];
    if (center is Map) {
      final cLat = (center['lat'] as num?)?.toDouble();
      final cLng = (center['lon'] as num?)?.toDouble();
      if (cLat != null && cLng != null) return (cLat, cLng);
    }
    return null;
  }

  static LandmarkKind _kindFor(Map<String, dynamic> tags) {
    final leisure = tags['leisure'] as String?;
    final amenity = tags['amenity'] as String?;
    final tourism = tags['tourism'] as String?;
    final shop = tags['shop'] as String?;
    if (leisure == 'park' || leisure == 'garden' || leisure == 'playground') {
      return LandmarkKind.park;
    }
    if (amenity == 'cafe') return LandmarkKind.cafe;
    if (shop == 'pet') return LandmarkKind.petShop;
    if (tourism == 'museum' || amenity == 'library' || amenity == 'arts_centre') {
      return LandmarkKind.culture;
    }
    if (amenity == 'community_centre') return LandmarkKind.plaza;
    return LandmarkKind.plaza;
  }

  static double _approxMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = (lat1 - lat2) * 111320;
    final dLng = (lng1 - lng2) * 111320 * 0.7;
    return dLat.abs() + dLng.abs();
  }
}

enum LandmarkKind { park, cafe, petShop, culture, plaza }

class Landmark {
  const Landmark({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.kind,
    this.osmTags = const {},
  });

  final String id;
  final String name;
  final double lat;
  final double lng;
  final LandmarkKind kind;
  final Map<String, dynamic> osmTags;
}

class _CacheEntry {
  const _CacheEntry({required this.at, required this.landmarks});

  final DateTime at;
  final List<Landmark> landmarks;
}
