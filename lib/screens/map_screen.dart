import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/client_settings.dart';
import '../config/map_basemap.dart';
import '../data/cat_repository.dart';
import '../game/geo_cell.dart';
import '../game/world_chunk_loader.dart';
import '../game/world_spawns.dart';
import '../screens/events/event_detail_sheet.dart';
import '../services/landmark_service.dart';
import '../services/lifecycle/client_clock.dart';
import '../services/lifecycle/sensor_work_tracker.dart';
import '../services/location_service.dart';
import '../services/nakama_client.dart';
import '../services/playable_location.dart';
import '../services/sync_service.dart';
import '../widgets/map/map_markers.dart';
import 'cat_den_sheet.dart';
import 'deck_pick_sheet.dart';
import 'landmark_hub_sheet.dart';
import 'nearby_sheet.dart';
import 'settings/client_settings_screen.dart';

const _streetZoom = 17.4;

/// Full-screen living world map — Catdex home (PoGo Map View language).
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.sync,
    required this.repository,
    required this.active,
    required this.location,
    required this.settings,
    required this.workTracker,
    this.onCatch,
    this.clock = const SystemClientClock(),
    this.landmarks,
  });

  final SyncService sync;
  final CatRepository repository;
  final bool active;
  final PlayableLocationProvider location;
  final ClientSettings settings;
  final SensorWorkTracker workTracker;
  final VoidCallback? onCatch;
  final ClientClock clock;
  final LandmarkService? landmarks;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  late final LandmarkService _landmarks =
      widget.landmarks ?? LandmarkService();
  late final WorldChunkLoader _chunks = WorldChunkLoader(landmarks: _landmarks);

  LocationFix? _fix;
  String? _focusCell;
  String? _error;
  String? _viewerId;
  bool _loading = true;
  bool _following = true;
  List<NakamaEvent> _events = const [];
  WorldSnapshot? _world;
  final _mapController = MapController();
  DateTime? _lastRefresh;
  int _requestGeneration = 0;
  int _failureCount = 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.location.addListener(_onLocationChanged);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || !widget.active) return;
      final world = _world;
      final now = widget.clock.now().toUtc();
      if (world != null && now.isAfter(world.spawnExpiresAt)) {
        unawaited(_rebuildWorld());
      }
    });
    if (widget.active) unawaited(_refresh());
  }

  void _onLocationChanged() {
    if (!mounted) return;
    final fix = widget.location.fix;
    if (fix == null) {
      setState(() {
        _fix = null;
        _error = widget.location.error;
        _loading = false;
      });
      return;
    }
    setState(() {
      _fix = fix;
      _error = null;
      _loading = false;
    });
    if (_following) {
      _mapController.move(LatLng(fix.lat, fix.lng), _streetZoom);
    }
    unawaited(_rebuildWorld());
    unawaited(_loadEvents(fix));
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    if (widget.active) {
      unawaited(_refresh());
    } else {
      _requestGeneration++;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) {
      unawaited(_refresh());
    } else {
      _requestGeneration++;
    }
  }

  @override
  void dispose() {
    widget.location.removeListener(_onLocationChanged);
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _requestGeneration++;
    _mapController.dispose();
    super.dispose();
  }

  bool _screenIsVisible() {
    if (!widget.active) return false;
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  Future<void> _refresh({bool force = false}) async {
    if (!_screenIsVisible()) return;
    final now = widget.clock.now();
    final last = _lastRefresh;
    final backoff = Duration(seconds: (1 << _failureCount.clamp(0, 6)) * 2);
    final floor = backoff > widget.settings.mapRefreshFloor
        ? backoff
        : widget.settings.mapRefreshFloor;
    if (!force && last != null && now.difference(last) < floor) return;
    _lastRefresh = now;
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _viewerId ??= await widget.sync.deviceUserId();
      final fix = await widget.location.current();
      if (!_requestIsCurrent(generation)) return;
      setState(() {
        _fix = fix;
        _loading = false;
        _following = true;
      });
      _mapController.move(LatLng(fix.lat, fix.lng), _streetZoom);
      _failureCount = 0;
      await Future.wait([
        _rebuildWorld(generation: generation),
        _loadEvents(fix, generation),
      ]);
    } catch (e) {
      if (!_requestIsCurrent(generation)) return;
      _failureCount++;
      setState(() {
        _error = '$e';
        _loading = false;
        _fix = widget.location.fix;
      });
    }
  }

  Future<void> _rebuildWorld({int? generation}) async {
    final fix = _fix;
    if (fix == null) return;
    final request = generation ?? _requestGeneration;
    final viewerId = _viewerId ?? 'anonymous';
    final now = widget.clock.now().toUtc();
    _chunks.invalidateExpired(now);
    // Prefer cached player chunk immediately so markers appear without delay.
    final cached = _chunks.peek(fix.cellId);
    if (cached != null && mounted && _requestIsCurrent(request)) {
      setState(() => _world = cached);
    }
    final world = await _chunks.ensureAround(
      lat: fix.lat,
      lng: fix.lng,
      cellId: fix.cellId,
      viewerId: viewerId,
      now: now,
      focusCellId: _focusCell,
    );
    if (!_requestIsCurrent(request)) return;
    if (!mounted) return;
    setState(() => _world = world);
  }

  bool _requestIsCurrent(int generation) =>
      mounted && _screenIsVisible() && generation == _requestGeneration;

  Future<void> _loadEvents(LocationFix fix, [int? generation]) async {
    if (!widget.active) return;
    final request = generation ?? _requestGeneration;
    widget.workTracker.eventRequested();
    try {
      final events = await widget.sync.nearbyEvents(
        GeoCell.neighborhood(fix.cellId),
      );
      if (!_requestIsCurrent(request)) return;
      setState(() => _events = events);
    } catch (_) {
      if (!_requestIsCurrent(request)) return;
      setState(() => _events = const []);
    }
  }

  void _recenter() {
    final fix = _fix;
    if (fix == null) {
      unawaited(_refresh(force: true));
      return;
    }
    _mapController.move(LatLng(fix.lat, fix.lng), _streetZoom);
    setState(() => _following = true);
  }

  Future<void> _showEvent(NakamaEvent event) async {
    final fix = _fix;
    if (fix == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: const Color(0xFF1C1917),
      builder: (context) => EventDetailSheet(
        event: event,
        fix: fix,
        onSummary: () => widget.sync.eventSummary(event.id),
        onContribute: (value) async {
          final result = await widget.sync.contributeEvent(
            eventId: event.id,
            amount: value.amount,
            h3Cell: fix.cellId,
            lat: fix.lat,
            lng: fix.lng,
            accuracyM: fix.accuracyM,
            type: value.type,
            squadId: value.squadId,
            checkpointId: value.checkpointId,
            stationary: value.stationary,
          );
          await _loadEvents(fix);
          return result;
        },
      ),
    );
  }

  void _onWildTap(WildCatSpawn spawn) {
    final fix = _fix;
    if (fix == null) return;
    if (!spawn.inRange(fix.lat, fix.lng)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A little closer…')),
      );
      return;
    }
    widget.onCatch?.call();
  }

  Future<void> _onEncounterTap(AreaEncounter encounter) async {
    final fix = _fix;
    if (fix == null) return;
    if (!encounter.inRange(fix.lat, fix.lng)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A little closer…')),
      );
      return;
    }
    await showDeckPickAndDuel(
      context,
      repository: widget.repository,
      sync: widget.sync,
      rivalName: encounter.displayName,
      npcEncounterId: encounter.id,
    );
  }

  Future<void> _onHubTap(LandmarkHub hub) async {
    await showLandmarkHubSheet(
      context,
      hub: hub,
      repository: widget.repository,
      sync: widget.sync,
    );
  }

  List<NearbyItem> _nearbyItems(LocationFix fix, WorldSnapshot world) {
    return [
      ...world.wildCats.map(
        (c) => NearbyItem(
          kind: NearbyKind.wildCat,
          id: c.id,
          title: c.name,
          inRange: c.inRange(fix.lat, fix.lng),
          onSelect: () => _onWildTap(c),
        ),
      ),
      ...world.encounters.map(
        (e) => NearbyItem(
          kind: NearbyKind.encounter,
          id: e.id,
          title: e.displayName,
          inRange: e.inRange(fix.lat, fix.lng),
          onSelect: () => _onEncounterTap(e),
        ),
      ),
      ...world.hubs.map(
        (h) => NearbyItem(
          kind: NearbyKind.hub,
          id: h.id,
          title: h.title,
          inRange: WorldDirector.metersBetween(fix.lat, fix.lng, h.lat, h.lng) <=
              160,
          onSelect: () => _onHubTap(h),
        ),
      ),
    ]..sort((a, b) {
      if (a.inRange != b.inRange) return a.inRange ? -1 : 1;
      return a.title.compareTo(b.title);
    });
  }

  Future<void> _openNearby() async {
    final fix = _fix;
    final world = _world;
    if (fix == null || world == null) return;
    await showNearbySheet(context, items: _nearbyItems(fix, world));
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFFFFBF5),
      isScrollControlled: true,
      builder: (_) => ClientSettingsScreen(
        settings: widget.settings,
        location: widget.location,
        onLocationChanged: () => _refresh(force: true),
      ),
    );
  }

  List<Marker> _eventMarkers() {
    final grouped = <String, List<NakamaEvent>>{};
    for (final event in _events) {
      grouped.putIfAbsent(event.h3Cell, () => []).add(event);
    }
    return grouped.values.map((events) {
      final event = events.first;
      final center = event.latitude == 0 && event.longitude == 0
          ? GeoCell.center(event.h3Cell)
          : (event.latitude, event.longitude);
      return Marker(
        point: LatLng(center.$1, center.$2),
        width: 56,
        height: 56,
        child: EventMapMarker(
          kind: event.kind,
          count: events.length,
          progress: event.goal == 0 ? 0 : event.progress / event.goal,
          onTap: () => _showEvent(event),
        ),
      );
    }).toList();
  }

  List<Marker> _worldMarkers(LocationFix fix, WorldSnapshot world) {
    return [
      ...world.hubs.map(
        (hub) => Marker(
          point: LatLng(hub.lat, hub.lng),
          width: 56,
          height: 56,
          child: LandmarkHubMarker(
            kind: hub.kind,
            progress: hub.progressRatio,
            onTap: () => _onHubTap(hub),
          ),
        ),
      ),
      ...world.wildCats.map(
        (spawn) => Marker(
          point: LatLng(spawn.lat, spawn.lng),
          width: 56,
          height: 56,
          child: WildCatMapMarker(
            inRange: spawn.inRange(fix.lat, fix.lng),
            onTap: () => _onWildTap(spawn),
          ),
        ),
      ),
      ...world.encounters.map(
        (enc) => Marker(
          point: LatLng(enc.lat, enc.lng),
          width: 52,
          height: 52,
          child: RivalMapMarker(
            inRange: enc.inRange(fix.lat, fix.lng),
            onTap: () => _onEncounterTap(enc),
          ),
        ),
      ),
    ];
  }

  String? get _activeHubTitle {
    final hubs = _world?.hubs;
    if (hubs == null || hubs.isEmpty) return null;
    return hubs.first.title;
  }

  @override
  Widget build(BuildContext context) {
    final fix = _fix;
    final world = _world;
    final needsPin = fix == null && widget.location.ready;
    final nearbyPreview = fix != null && world != null
        ? _nearbyItems(fix, world).take(3).toList()
        : const <NearbyItem>[];

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: fix != null
                ? LatLng(fix.lat, fix.lng)
                : const LatLng(20, 0),
            initialZoom: fix != null ? _streetZoom : 2.5,
            onPositionChanged: (camera, hasGesture) {
              if (hasGesture && _following) {
                setState(() => _following = false);
              }
              if (hasGesture) {
                final center = camera.center;
                final cell = GeoCell.fromLatLng(
                  center.latitude,
                  center.longitude,
                );
                if (cell != _focusCell) {
                  _focusCell = cell;
                  unawaited(_rebuildWorld());
                }
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: MapBasemap.rasterUrlTemplate,
              userAgentPackageName: 'com.catdex.catdex',
              retinaMode: true,
            ),
            if (fix != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: LatLng(fix.lat, fix.lng),
                    radius: 120,
                    useRadiusInMeter: true,
                    color: const Color(0xFFF97316).withValues(alpha: .12),
                    borderColor:
                        const Color(0xFFF97316).withValues(alpha: .55),
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                ..._eventMarkers(),
                if (fix != null && world != null) ..._worldMarkers(fix, world),
                if (fix != null)
                  Marker(
                    point: LatLng(fix.lat, fix.lng),
                    width: 76,
                    height: 76,
                    child: UserMapPointer(heading: fix.heading),
                  ),
              ],
            ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution(MapBasemap.attribution),
              ],
            ),
          ],
        ),
        if (needsPin)
          _PinHint(
            onOpenSettings: _openSettings,
            onRetry: () async {
              await widget.location.clearManualAndRetryDevice();
              await _refresh(force: true);
            },
          ),
        if (_loading && fix == null && !needsPin)
          const Center(child: CircularProgressIndicator())
        else if (fix != null)
          _MapHud(
            hubTitle: _activeHubTitle,
            nearbyPreview: nearbyPreview,
            following: _following,
            onRecenter: _recenter,
            onDen: () => showCatDenSheet(
              context,
              repository: widget.repository,
            ),
            onNearby: _openNearby,
            onSettings: _openSettings,
            onCatch: () {
              final count = world?.wildCats
                      .where((w) => w.inRange(fix.lat, fix.lng))
                      .length ??
                  0;
              if (count > 0) {
                widget.onCatch?.call();
              } else {
                _openNearby();
              }
            },
          ),
        if (_error != null && fix == null)
          Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  elevation: 2,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Couldn’t place you. Open settings to drop a pin.',
                      style: TextStyle(color: Color(0xFF1C1917)),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PinHint extends StatelessWidget {
  const _PinHint({required this.onOpenSettings, required this.onRetry});

  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Material(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.explore, size: 40, color: Color(0xFFEA580C)),
                const SizedBox(height: 12),
                const Text(
                  'Find your street',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This device has no GPS. Set your spot in Settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF57534E)),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onOpenSettings,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEA580C),
                  ),
                  child: const Text('Open settings'),
                ),
                TextButton(onPressed: onRetry, child: const Text('Try again')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapHud extends StatelessWidget {
  const _MapHud({
    required this.nearbyPreview,
    required this.following,
    required this.onRecenter,
    required this.onDen,
    required this.onNearby,
    required this.onSettings,
    required this.onCatch,
    this.hubTitle,
  });

  final String? hubTitle;
  final List<NearbyItem> nearbyPreview;
  final bool following;
  final VoidCallback onRecenter;
  final VoidCallback onDen;
  final VoidCallback onNearby;
  final VoidCallback onSettings;
  final VoidCallback onCatch;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
        child: Column(
          children: [
            if (hubTitle != null)
              Align(
                alignment: Alignment.topCenter,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(999),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.place,
                          size: 16,
                          color: Color(0xFFEA580C),
                        ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(
                            hubTitle!,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1C1917),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  children: [
                    _RoundFab(
                      icon: Icons.person,
                      onTap: onSettings,
                      filled: false,
                    ),
                    const SizedBox(height: 10),
                    _RoundFab(
                      icon: following ? Icons.gps_fixed : Icons.gps_not_fixed,
                      onTap: onRecenter,
                      filled: following,
                    ),
                  ],
                ),
                const Spacer(),
                _DenOrb(onTap: onDen),
                const Spacer(),
                Column(
                  children: [
                    _RoundFab(
                      icon: Icons.camera_alt,
                      onTap: onCatch,
                      filled: true,
                    ),
                    const SizedBox(height: 10),
                    _NearbyPeek(
                      items: nearbyPreview,
                      onOpen: onNearby,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DenOrb extends StatelessWidget {
  const _DenOrb({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEA580C),
      shape: const CircleBorder(),
      elevation: 6,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 78,
          height: 78,
          child: Icon(Icons.home_filled, color: Colors.white, size: 36),
        ),
      ),
    );
  }
}

class _RoundFab extends StatelessWidget {
  const _RoundFab({
    required this.icon,
    required this.onTap,
    required this.filled,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? const Color(0xFFEA580C) : Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            color: filled ? Colors.white : const Color(0xFF1C1917),
          ),
        ),
      ),
    );
  }
}

class _NearbyPeek extends StatelessWidget {
  const _NearbyPeek({required this.items, required this.onOpen});

  final List<NearbyItem> items;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      elevation: 3,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (items.isEmpty)
                const Icon(Icons.radar, color: Color(0xFF78716C), size: 22)
              else
                ...items.take(3).map((item) {
                  final color = switch (item.kind) {
                    NearbyKind.wildCat => const Color(0xFFF97316),
                    NearbyKind.encounter => const Color(0xFFEF4444),
                    NearbyKind.hub => const Color(0xFFF59E0B),
                  };
                  final icon = switch (item.kind) {
                    NearbyKind.wildCat => Icons.pets,
                    NearbyKind.encounter => Icons.sports_mma,
                    NearbyKind.hub => Icons.place,
                  };
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: CircleAvatar(
                      radius: 12,
                      backgroundColor: color,
                      child: Icon(icon, size: 14, color: Colors.white),
                    ),
                  );
                }),
              const SizedBox(width: 4),
              const Icon(Icons.expand_less, color: Color(0xFF1C1917)),
            ],
          ),
        ),
      ),
    );
  }
}
