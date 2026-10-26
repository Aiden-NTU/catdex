import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClientSettings extends ChangeNotifier {
  ClientSettings._(this._preferences)
    : _lowPower = _preferences.getBool(_lowPowerKey) ?? false,
      _reducedMotion = _preferences.getBool(_reducedMotionKey) ?? false;

  static const _lowPowerKey = 'client.lowPower';
  static const _reducedMotionKey = 'client.reducedMotion';

  final SharedPreferences _preferences;
  bool _lowPower;
  bool _reducedMotion;

  static Future<ClientSettings> load() async =>
      ClientSettings._(await SharedPreferences.getInstance());

  bool get lowPower => _lowPower;
  bool get reducedMotion => _reducedMotion;
  int get previewFrameInterval => _lowPower ? 12 : 4;
  Duration get mapRefreshFloor =>
      Duration(minutes: _lowPower ? 5 : 2);
  Duration get battlePollInterval =>
      Duration(seconds: _lowPower ? 8 : 2);

  Future<void> setLowPower(bool value) async {
    if (_lowPower == value) return;
    _lowPower = value;
    notifyListeners();
    await _preferences.setBool(_lowPowerKey, value);
  }

  Future<void> setReducedMotion(bool value) async {
    if (_reducedMotion == value) return;
    _reducedMotion = value;
    notifyListeners();
    await _preferences.setBool(_reducedMotionKey, value);
  }
}
