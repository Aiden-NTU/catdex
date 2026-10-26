import 'dart:io';

import 'package:flutter/foundation.dart';

/// Compile-time switches for the desktop-only client simulator.
///
/// Enable with `--dart-define=CATDEX_SIMULATOR=true`. Release builds always
/// ignore the flag so simulator data cannot bypass production trust checks.
abstract final class ClientQualityConfig {
  static const simulatorRequested = bool.fromEnvironment('CATDEX_SIMULATOR');
  static const simulatedAccuracyMeters = int.fromEnvironment(
    'CATDEX_SIMULATOR_ACCURACY_M',
    defaultValue: 8,
  );
  static double get simulatedAccuracyM => simulatedAccuracyMeters.toDouble();
  static const simulatedStepSeconds = int.fromEnvironment(
    'CATDEX_SIMULATOR_STEP_SECONDS',
    defaultValue: 5,
  );
  static const simulatedNetworkOnline = bool.fromEnvironment(
    'CATDEX_SIMULATOR_NETWORK_ONLINE',
    defaultValue: true,
  );

  static bool get simulatorEnabled =>
      simulatorRequested &&
      !kReleaseMode &&
      !kIsWeb &&
      (Platform.isLinux || Platform.isMacOS || Platform.isWindows);
}
