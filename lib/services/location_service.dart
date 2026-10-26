import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../config/client_quality_config.dart';
import '../game/geo_cell.dart';
import 'lifecycle/client_clock.dart';
import 'lifecycle/sensor_work_tracker.dart';

class LocationFix {
  const LocationFix({
    required this.lat,
    required this.lng,
    required this.cellId,
    required this.accuracyM,
    required this.capturedAt,
    this.isSimulated = false,
    this.heading,
    this.headingAccuracy,
  });

  final double lat;
  final double lng;
  final String cellId;
  final double accuracyM;
  final DateTime capturedAt;
  final bool isSimulated;
  final double? heading;
  final double? headingAccuracy;
}

abstract interface class LocationProvider {
  Future<LocationFix> current();
}

class LocationService implements LocationProvider {
  LocationService({
    this.simulatedFix,
    ClientClock clock = const SystemClientClock(),
    SensorWorkTracker? tracker,
    Duration cacheLifetime = const Duration(minutes: 2),
  }) : _clock = clock,
       _tracker = tracker,
       _cacheLifetime = cacheLifetime;

  final LocationFix? simulatedFix;
  final ClientClock _clock;
  final SensorWorkTracker? _tracker;
  final Duration _cacheLifetime;
  LocationFix? _cached;

  /// Compile-time development simulation; never enabled in release by default.
  static const demoLat = 51.5074;
  static const demoLng = -0.1278;
  static const _developmentMode = bool.fromEnvironment(
    'CATDEX_DEVELOPMENT_MODE',
  );
  static final _simLat =
      double.tryParse(
        const String.fromEnvironment(
          'CATDEX_SIMULATED_LAT',
          defaultValue: '$demoLat',
        ),
      ) ??
      demoLat;
  static final _simLng =
      double.tryParse(
        const String.fromEnvironment(
          'CATDEX_SIMULATED_LNG',
          defaultValue: '$demoLng',
        ),
      ) ??
      demoLng;

  factory LocationService.developmentAware() {
    if (ClientQualityConfig.simulatorEnabled) {
      return LocationService(
        simulatedFix: SimulatorLocationProvider.defaultRoute().peek(),
      );
    }
    final desktop = Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    if (_developmentMode && !kReleaseMode && desktop) {
      return LocationService(
        simulatedFix: LocationFix(
          lat: _simLat,
          lng: _simLng,
          cellId: GeoCell.fromLatLng(_simLat, _simLng),
          accuracyM: 5,
          capturedAt: DateTime.now().toUtc(),
          isSimulated: true,
          heading: 35,
          headingAccuracy: 8,
        ),
      );
    }
    return LocationService();
  }

  Future<LocationFix> current() async {
    final injected = simulatedFix;
    if (injected != null) return injected;

    final cached = _cached;
    if (cached != null &&
        _clock.now().difference(cached.capturedAt) <= _cacheLifetime) {
      return cached;
    }
    _tracker?.locationStarted();
    try {
      return _cached = await _readPosition();
    } finally {
      _tracker?.locationStopped();
    }
  }

  Future<LocationFix> _readPosition() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw StateError('Location permission denied');
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Location services disabled');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 8),
      ),
    );
    return LocationFix(
      lat: pos.latitude,
      lng: pos.longitude,
      cellId: GeoCell.fromLatLng(pos.latitude, pos.longitude),
      accuracyM: pos.accuracy,
      capturedAt: pos.timestamp.toUtc(),
      heading: pos.heading.isFinite && pos.heading >= 0 ? pos.heading : null,
      headingAccuracy: pos.headingAccuracy.isFinite && pos.headingAccuracy >= 0
          ? pos.headingAccuracy
          : null,
    );
  }
}

/// Deterministic route playback for Linux/desktop integration exercises.
class SimulatorLocationProvider implements LocationProvider {
  SimulatorLocationProvider({
    required List<(double, double)> route,
    ClientClock clock = const SystemClientClock(),
    double? accuracyM,
    this.step = const Duration(
      seconds: ClientQualityConfig.simulatedStepSeconds,
    ),
    this.networkOnline = ClientQualityConfig.simulatedNetworkOnline,
    SensorWorkTracker? tracker,
  }) : assert(route.length > 1),
       accuracyM = accuracyM ?? ClientQualityConfig.simulatedAccuracyM,
       _route = route,
       _clock = clock,
       _tracker = tracker;

  factory SimulatorLocationProvider.defaultRoute({
    ClientClock clock = const SystemClientClock(),
    SensorWorkTracker? tracker,
  }) => SimulatorLocationProvider(
    route: const [
      (51.5074, -0.1278),
      (51.5078, -0.1269),
      (51.5083, -0.1260),
      (51.5088, -0.1252),
    ],
    clock: clock,
    tracker: tracker,
  );

  final List<(double, double)> _route;
  final ClientClock _clock;
  final SensorWorkTracker? _tracker;
  final double accuracyM;
  final Duration step;
  final bool networkOnline;
  int _index = 0;

  LocationFix peek() => _fix(_route[_index]);

  void walk() {
    _index = (_index + 1) % _route.length;
  }

  @override
  Future<LocationFix> current() async {
    _tracker?.locationStarted();
    try {
      return _fix(_route[_index]);
    } finally {
      _tracker?.locationStopped();
    }
  }

  LocationFix _fix((double, double) point) => LocationFix(
    lat: point.$1,
    lng: point.$2,
    cellId: GeoCell.fromLatLng(point.$1, point.$2),
    accuracyM: accuracyM,
    capturedAt: _clock.now(),
    isSimulated: true,
    heading: 65,
    headingAccuracy: 5,
  );
}
