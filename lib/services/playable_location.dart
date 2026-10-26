import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../game/geo_cell.dart';
import 'lifecycle/sensor_work_tracker.dart';
import 'location_service.dart';

enum LocationSource { device, ipApproximate, manual, unset }

/// Location for the live map: device GPS when available, otherwise an honest
/// IP estimate or a manual pin (required on most Linux desktops).
class PlayableLocationProvider extends ChangeNotifier
    implements LocationProvider {
  PlayableLocationProvider({
    LocationProvider? device,
    SensorWorkTracker? tracker,
    http.Client? httpClient,
  }) : _device = device ?? LocationService(tracker: tracker),
       _http = httpClient ?? http.Client();

  static const _prefsLat = 'catdex.manual_lat';
  static const _prefsLng = 'catdex.manual_lng';
  static const _prefsSource = 'catdex.location_source';

  final LocationProvider _device;
  final http.Client _http;

  LocationFix? _fix;
  LocationSource _source = LocationSource.unset;
  String? _error;
  bool _ready = false;

  LocationFix? get fix => _fix;
  LocationSource get source => _source;
  String? get error => _error;
  bool get ready => _ready;
  bool get isManual => _source == LocationSource.manual;
  bool get isApproximate => _source == LocationSource.ipApproximate;

  Future<void> bootstrap() async {
    _error = null;
    // 1) Saved manual pin (desktop playtesting).
    final prefs = await SharedPreferences.getInstance();
    final savedLat = prefs.getDouble(_prefsLat);
    final savedLng = prefs.getDouble(_prefsLng);
    if (savedLat != null && savedLng != null) {
      _setFix(
        _manualFix(savedLat, savedLng),
        LocationSource.manual,
        persist: false,
      );
      _ready = true;
      notifyListeners();
      return;
    }

    // 2) Real device / OS location (phones; rare on Linux without GeoClue).
    try {
      final deviceFix = await _device.current();
      _setFix(deviceFix, LocationSource.device, persist: false);
      _ready = true;
      notifyListeners();
      return;
    } on Object catch (e) {
      debugPrint('Device location unavailable: $e');
    }

    // 3) Coarse IP geolocation — labeled approximate, not GPS.
    try {
      final approx = await _ipApproximate();
      if (approx != null) {
        _setFix(approx, LocationSource.ipApproximate, persist: false);
        _ready = true;
        notifyListeners();
        return;
      }
    } on Object catch (e) {
      debugPrint('IP approximate location failed: $e');
    }

    _error =
        'No GPS on this machine. Long-press the map to drop your pin '
        '(or enable OS location services).';
    _ready = true;
    notifyListeners();
  }

  @override
  Future<LocationFix> current() async {
    final existing = _fix;
    if (existing != null) return existing;
    await bootstrap();
    final after = _fix;
    if (after != null) return after;
    throw StateError(
      _error ??
          'Location not set. Long-press the map to place yourself.',
    );
  }

  /// Developer / desktop: place or drag the player to an exact lat/lng.
  Future<void> setManual(double lat, double lng) async {
    _setFix(_manualFix(lat, lng), LocationSource.manual, persist: true);
    notifyListeners();
  }

  Future<void> clearManualAndRetryDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsLat);
    await prefs.remove(_prefsLng);
    await prefs.remove(_prefsSource);
    _fix = null;
    _source = LocationSource.unset;
    await bootstrap();
  }

  void _setFix(LocationFix fix, LocationSource source, {required bool persist}) {
    _fix = fix;
    _source = source;
    _error = null;
    _ready = true;
    if (persist) {
      SharedPreferences.getInstance().then((prefs) async {
        await prefs.setDouble(_prefsLat, fix.lat);
        await prefs.setDouble(_prefsLng, fix.lng);
        await prefs.setString(_prefsSource, source.name);
      });
    }
  }

  LocationFix _manualFix(double lat, double lng) => LocationFix(
    lat: lat,
    lng: lng,
    cellId: GeoCell.fromLatLng(lat, lng),
    accuracyM: 5,
    capturedAt: DateTime.now().toUtc(),
    isSimulated: true,
    heading: null,
  );

  Future<LocationFix?> _ipApproximate() async {
    final response = await _http
        .get(
          Uri.parse('https://ipapi.co/json/'),
          headers: const {'User-Agent': 'Catdex/1.0'},
        )
        .timeout(const Duration(seconds: 6));
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    final json = jsonDecode(response.body);
    if (json is! Map) return null;
    final lat = (json['latitude'] as num?)?.toDouble();
    final lng = (json['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LocationFix(
      lat: lat,
      lng: lng,
      cellId: GeoCell.fromLatLng(lat, lng),
      accuracyM: 5000,
      capturedAt: DateTime.now().toUtc(),
      isSimulated: false,
      heading: null,
    );
  }
}
