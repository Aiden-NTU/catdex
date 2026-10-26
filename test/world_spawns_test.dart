import 'package:catdex/game/world_spawns.dart';
import 'package:catdex/services/landmark_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared hubs + personal cats + area/cohort encounters', () {
    const lat = 51.5074;
    const lng = -0.1278;
    const cell = 'cell-a';
    final now = DateTime.utc(2026, 10, 26, 14, 0);
    final landmarks = const [
      Landmark(
        id: 'n-1',
        name: 'St James Park',
        lat: 51.508,
        lng: -0.128,
        kind: LandmarkKind.park,
      ),
      Landmark(
        id: 'n-2',
        name: 'Whiskers Café',
        lat: 51.507,
        lng: -0.126,
        kind: LandmarkKind.cafe,
      ),
    ];

    final alice = WorldDirector.snapshot(
      lat: lat,
      lng: lng,
      cellId: cell,
      now: now,
      viewerId: 'alice',
      landmarks: landmarks,
    );
    final bob = WorldDirector.snapshot(
      lat: lat,
      lng: lng,
      cellId: cell,
      now: now,
      viewerId: 'bob',
      landmarks: landmarks,
    );

    expect(alice.hubs.map((h) => h.title), bob.hubs.map((h) => h.title));
    expect(alice.wildCats.first.id, isNot(bob.wildCats.first.id));

    final aliceArea = alice.encounters
        .where((e) => e.scope == SpawnScope.area)
        .map((e) => e.id)
        .toSet();
    final bobArea = bob.encounters
        .where((e) => e.scope == SpawnScope.area)
        .map((e) => e.id)
        .toSet();
    expect(aliceArea, bobArea);
  });

  test('no landmarks means no fake hubs', () {
    final world = WorldDirector.snapshot(
      lat: 24.0,
      lng: 14.0,
      cellId: 'desert',
      now: DateTime.utc(2026, 10, 26, 14, 0),
      viewerId: 'solo',
      landmarks: const [],
    );
    expect(world.hubs, isEmpty);
    expect(world.wildCats, isNotEmpty);
    expect(world.encounters, isNotEmpty);
  });
}
