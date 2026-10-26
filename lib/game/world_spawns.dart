import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../services/landmark_service.dart';

/// Living-world spawns with honest visibility scopes.
///
/// - [SpawnScope.personal] — only this device (seeded with [viewerId])
/// - [SpawnScope.area] — everyone in the same H3 cell + time window
/// - [SpawnScope.cohort] — a small subset of players in the cell (~1/4)
///
/// Landmark hubs come only from real OSM places (shared). No fake players.
class WorldDirector {
  WorldDirector._();

  static const Distance _distance = Distance();
  static const spawnWindow = Duration(minutes: 12);

  static int timeBucket(DateTime now, Duration window) =>
      now.toUtc().millisecondsSinceEpoch ~/ window.inMilliseconds;

  static DateTime bucketEnds(DateTime now, Duration window) {
    final bucket = timeBucket(now, window);
    return DateTime.fromMillisecondsSinceEpoch(
      (bucket + 1) * window.inMilliseconds,
      isUtc: true,
    );
  }

  /// [viewerId] should be a stable device/user id so personal spawns differ
  /// per player while area/cohort spawns stay shared.
  static WorldSnapshot snapshot({
    required double lat,
    required double lng,
    required String cellId,
    required DateTime now,
    required String viewerId,
    List<Landmark> landmarks = const [],
  }) {
    final bucket = timeBucket(now, spawnWindow);
    final expires = bucketEnds(now, spawnWindow);
    final cohort = viewerId.hashCode.abs() % 4;

    final hubs = landmarks.take(10).map((place) {
      final kind = switch (place.kind) {
        LandmarkKind.cafe => 'cat_cafe_rally',
        LandmarkKind.park => 'laser_pointer_chase',
        LandmarkKind.petShop => 'cat_cafe_rally',
        LandmarkKind.culture => 'cardboard_fortress',
        LandmarkKind.plaza => 'cardboard_fortress',
      };
      return LandmarkHub(
        id: 'hub-${place.id}',
        title: place.name,
        subtitle: _hubSubtitle(place.kind),
        kind: kind,
        lat: place.lat,
        lng: place.lng,
        startsAt: expires.subtract(spawnWindow),
        endsAt: expires,
        goal: 40 + (place.id.hashCode.abs() % 80),
        progress: (bucket * 7 + place.id.hashCode).abs() % 25,
      );
    }).toList(growable: false);

    final personal = _wildCats(
      lat: lat,
      lng: lng,
      cellId: cellId,
      bucket: bucket,
      expires: expires,
      hubs: hubs,
      scopeSeed: viewerId.hashCode,
      scope: SpawnScope.personal,
      count: 3,
    );

    final areaEncounters = _encounters(
      lat: lat,
      lng: lng,
      cellId: cellId,
      bucket: bucket,
      expires: expires,
      hubs: hubs,
      scopeSeed: cellId.hashCode,
      scope: SpawnScope.area,
      count: hubs.isEmpty ? 1 : 2,
    );

    final cohortEncounters = _encounters(
      lat: lat,
      lng: lng,
      cellId: cellId,
      bucket: bucket,
      expires: expires,
      hubs: hubs,
      scopeSeed: cellId.hashCode ^ (cohort * 7919),
      scope: SpawnScope.cohort,
      count: 1,
      namePrefix: 'Cohort',
    );

    return WorldSnapshot(
      wildCats: personal,
      encounters: [...areaEncounters, ...cohortEncounters],
      hubs: hubs,
      spawnExpiresAt: expires,
      landmarkCount: landmarks.length,
      cohortIndex: cohort,
    );
  }

  static String _hubSubtitle(LandmarkKind kind) => switch (kind) {
    LandmarkKind.cafe => 'Shared café rally (everyone nearby sees this)',
    LandmarkKind.park => 'Shared park chase (everyone nearby sees this)',
    LandmarkKind.petShop => 'Shared pet-shop meetup',
    LandmarkKind.culture => 'Shared venue fortress',
    LandmarkKind.plaza => 'Shared community hub',
  };

  static List<WildCatSpawn> _wildCats({
    required double lat,
    required double lng,
    required String cellId,
    required int bucket,
    required DateTime expires,
    required List<LandmarkHub> hubs,
    required int scopeSeed,
    required SpawnScope scope,
    required int count,
  }) {
    final rng = math.Random(scopeSeed ^ (bucket * 9176) ^ 0xC47);
    final breeds = const [
      'Tabby',
      'Siamese',
      'Maine Coon',
      'British Shorthair',
      'Calico',
      'Bombay',
      'Ragdoll',
      'Bengal',
    ];
    final anchors = <LatLng>[
      LatLng(lat, lng),
      ...hubs.take(2).map((h) => LatLng(h.lat, h.lng)),
    ];
    return List.generate(count, (i) {
      final anchor = anchors[i % anchors.length];
      final bearing = rng.nextDouble() * 360;
      final meters = 28.0 + rng.nextDouble() * 95;
      final point = _distance.offset(anchor, meters, bearing);
      return WildCatSpawn(
        id: 'wild-$scope-$cellId-$bucket-$i-${scopeSeed.abs() % 100000}',
        name: breeds[rng.nextInt(breeds.length)],
        lat: point.latitude,
        lng: point.longitude,
        stars: 1 + rng.nextInt(3),
        catchableMeters: 120,
        expiresAt: expires,
        scope: scope,
      );
    });
  }

  static List<AreaEncounter> _encounters({
    required double lat,
    required double lng,
    required String cellId,
    required int bucket,
    required DateTime expires,
    required List<LandmarkHub> hubs,
    required int scopeSeed,
    required SpawnScope scope,
    required int count,
    String namePrefix = 'Area',
  }) {
    final rng = math.Random(scopeSeed ^ bucket ^ 0xBEEF);
    final names = const [
      'Wandering Trainer',
      'Park Scout',
      'Café Challenger',
      'Night Patrol',
    ];
    return List.generate(count, (i) {
      LatLng anchor;
      if (hubs.isNotEmpty) {
        anchor = LatLng(hubs[i % hubs.length].lat, hubs[i % hubs.length].lng);
      } else {
        anchor = LatLng(lat, lng);
      }
      final bearing = rng.nextDouble() * 360;
      final meters = 50.0 + rng.nextDouble() * 140;
      final point = _distance.offset(anchor, meters, bearing);
      final base = names[rng.nextInt(names.length)];
      return AreaEncounter(
        id: 'enc-$scope-$cellId-$bucket-$i',
        displayName: scope == SpawnScope.cohort ? '$namePrefix $base' : base,
        lat: point.latitude,
        lng: point.longitude,
        challengeMeters: 140,
        expiresAt: expires,
        scope: scope,
      );
    });
  }

  static double metersBetween(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) =>
      _distance.as(
        LengthUnit.Meter,
        LatLng(lat1, lng1),
        LatLng(lat2, lng2),
      );
}

enum SpawnScope {
  /// Only this viewer.
  personal,

  /// Everyone in the H3 cell for this time window.
  area,

  /// A small cohort (~25%) of players in the cell.
  cohort,
}

class WorldSnapshot {
  const WorldSnapshot({
    required this.wildCats,
    required this.encounters,
    required this.hubs,
    required this.spawnExpiresAt,
    required this.landmarkCount,
    required this.cohortIndex,
  });

  final List<WildCatSpawn> wildCats;
  final List<AreaEncounter> encounters;
  final List<LandmarkHub> hubs;
  final DateTime spawnExpiresAt;
  final int landmarkCount;
  final int cohortIndex;
}

class WildCatSpawn {
  const WildCatSpawn({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.stars,
    required this.catchableMeters,
    required this.expiresAt,
    required this.scope,
  });

  final String id;
  final String name;
  final double lat;
  final double lng;
  final int stars;
  final double catchableMeters;
  final DateTime expiresAt;
  final SpawnScope scope;

  bool inRange(double playerLat, double playerLng) =>
      WorldDirector.metersBetween(playerLat, playerLng, lat, lng) <=
      catchableMeters;

  Duration ttl(DateTime now) {
    final left = expiresAt.difference(now.toUtc());
    return left.isNegative ? Duration.zero : left;
  }
}

class AreaEncounter {
  const AreaEncounter({
    required this.id,
    required this.displayName,
    required this.lat,
    required this.lng,
    required this.challengeMeters,
    required this.expiresAt,
    required this.scope,
  });

  final String id;
  final String displayName;
  final double lat;
  final double lng;
  final double challengeMeters;
  final DateTime expiresAt;
  final SpawnScope scope;

  bool inRange(double playerLat, double playerLng) =>
      WorldDirector.metersBetween(playerLat, playerLng, lat, lng) <=
      challengeMeters;

  Duration ttl(DateTime now) {
    final left = expiresAt.difference(now.toUtc());
    return left.isNegative ? Duration.zero : left;
  }
}

class LandmarkHub {
  const LandmarkHub({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.lat,
    required this.lng,
    required this.startsAt,
    required this.endsAt,
    required this.goal,
    required this.progress,
  });

  final String id;
  final String title;
  final String subtitle;
  final String kind;
  final double lat;
  final double lng;
  final DateTime startsAt;
  final DateTime endsAt;
  final int goal;
  final int progress;

  double get progressRatio => goal == 0 ? 0 : progress / goal;
}
