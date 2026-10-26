import 'geo_cell.dart';
import 'world_spawns.dart';
import '../services/landmark_service.dart';

/// Minecraft-style chunk cache: each H3 cell is a chunk of world content.
class WorldChunkLoader {
  WorldChunkLoader({LandmarkService? landmarks})
    : _landmarks = landmarks ?? LandmarkService();

  final LandmarkService _landmarks;
  final Map<String, WorldSnapshot> _chunks = {};
  final Set<String> _loading = {};

  WorldSnapshot? peek(String cellId) => _chunks[cellId];

  /// Ensure player cell + ring (and optional focus cell from pan) are loaded.
  Future<WorldSnapshot> ensureAround({
    required double lat,
    required double lng,
    required String cellId,
    required String viewerId,
    required DateTime now,
    String? focusCellId,
  }) async {
    final cells = <String>{
      ...GeoCell.neighborhood(cellId),
      if (focusCellId != null) ...GeoCell.neighborhood(focusCellId),
    };
    await Future.wait(cells.map((id) => _loadCell(id, viewerId, now)));

    // Merge visible chunks into one snapshot for the map.
    final wild = <WildCatSpawn>[];
    final encounters = <AreaEncounter>[];
    final hubs = <LandmarkHub>[];
    DateTime expires = now.add(WorldDirector.spawnWindow);
    var landmarkCount = 0;
    for (final id in cells) {
      final chunk = _chunks[id];
      if (chunk == null) continue;
      wild.addAll(chunk.wildCats);
      encounters.addAll(chunk.encounters);
      hubs.addAll(chunk.hubs);
      if (chunk.spawnExpiresAt.isBefore(expires)) {
        expires = chunk.spawnExpiresAt;
      }
      landmarkCount += chunk.landmarkCount;
    }
    return WorldSnapshot(
      wildCats: wild,
      encounters: encounters,
      hubs: hubs,
      spawnExpiresAt: expires,
      landmarkCount: landmarkCount,
      cohortIndex: viewerId.hashCode.abs() % 4,
    );
  }

  Future<void> _loadCell(
    String cellId,
    String viewerId,
    DateTime now,
  ) async {
    final existing = _chunks[cellId];
    if (existing != null && existing.spawnExpiresAt.isAfter(now)) return;
    if (_loading.contains(cellId)) return;
    _loading.add(cellId);
    try {
      final center = GeoCell.center(cellId);
      final places = await _landmarks.nearby(
        lat: center.$1,
        lng: center.$2,
        cellId: cellId,
      );
      _chunks[cellId] = WorldDirector.snapshot(
        lat: center.$1,
        lng: center.$2,
        cellId: cellId,
        now: now,
        viewerId: viewerId,
        landmarks: places,
      );
    } finally {
      _loading.remove(cellId);
    }
  }

  void invalidateExpired(DateTime now) {
    _chunks.removeWhere((_, snap) => snap.spawnExpiresAt.isBefore(now));
  }
}
