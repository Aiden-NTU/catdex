import 'package:flutter/foundation.dart';

/// Observable accounting used by tests and diagnostics to prove that sensor
/// work is quiescent while a feature is inactive.
class SensorWorkTracker extends ChangeNotifier {
  int cameraStarts = 0;
  int cameraStops = 0;
  int inferenceRuns = 0;
  int locationRequests = 0;
  int eventRequests = 0;
  int battlePolls = 0;

  int activeCameraSessions = 0;
  int activeLocationRequests = 0;

  void cameraStarted() {
    cameraStarts++;
    activeCameraSessions++;
    notifyListeners();
  }

  void cameraStopped() {
    cameraStops++;
    activeCameraSessions = (activeCameraSessions - 1).clamp(0, 1 << 30);
    notifyListeners();
  }

  void inferenceRan() {
    inferenceRuns++;
    notifyListeners();
  }

  void locationStarted() {
    locationRequests++;
    activeLocationRequests++;
    notifyListeners();
  }

  void locationStopped() {
    activeLocationRequests = (activeLocationRequests - 1).clamp(0, 1 << 30);
    notifyListeners();
  }

  void eventRequested() {
    eventRequests++;
    notifyListeners();
  }

  void battlePolled() {
    battlePolls++;
    notifyListeners();
  }
}
