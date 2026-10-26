import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../models/scan_result.dart';

/// Cheap CPU checks before / alongside neural nets.
class QualityGate {
  QualityGate({
    this.minBlur = 40.0,
    this.minBoxAreaRatio = 0.08,
    this.maxBoxAreaRatio = 0.95,
    this.minConfidence = 0.45,
    this.stabilityFrames = 5,
    this.minIoU = 0.55,
  });

  final double minBlur;
  final double minBoxAreaRatio;
  final double maxBoxAreaRatio;
  final double minConfidence;
  final int stabilityFrames;
  final double minIoU;

  final List<DetectionBox> _recentBoxes = [];

  void resetStability() => _recentBoxes.clear();

  /// Laplacian-variance style blur score on grayscale crop.
  static double blurScore(img.Image image) {
    if (image.width < 3 || image.height < 3) return 0;
    final gray = img.grayscale(image);
    var sum = 0.0;
    var sumSq = 0.0;
    var count = 0;
    for (var y = 1; y < gray.height - 1; y++) {
      for (var x = 1; x < gray.width - 1; x++) {
        final c = gray.getPixel(x, y).luminance.toDouble();
        final l = gray.getPixel(x - 1, y).luminance.toDouble();
        final r = gray.getPixel(x + 1, y).luminance.toDouble();
        final t = gray.getPixel(x, y - 1).luminance.toDouble();
        final b = gray.getPixel(x, y + 1).luminance.toDouble();
        final lap = (l + r + t + b) - 4 * c;
        sum += lap;
        sumSq += lap * lap;
        count++;
      }
    }
    if (count == 0) return 0;
    final mean = sum / count;
    return (sumSq / count) - mean * mean;
  }

  QualityGateResult evaluate({
    required img.Image fullFrame,
    DetectionBox? box,
    img.Image? crop,
  }) {
    if (box == null || box.score < minConfidence) {
      resetStability();
      return const QualityGateResult(
        passed: false,
        hint: 'Point at a cat',
      );
    }

    final areaRatio = box.area; // box is already normalized 0–1
    if (areaRatio < minBoxAreaRatio) {
      resetStability();
      return QualityGateResult(
        passed: false,
        hint: 'Move closer',
        boxAreaRatio: areaRatio,
      );
    }
    if (areaRatio > maxBoxAreaRatio) {
      resetStability();
      return QualityGateResult(
        passed: false,
        hint: 'Step back a little',
        boxAreaRatio: areaRatio,
      );
    }

    final analyzed = crop ?? fullFrame;
    final blur = blurScore(analyzed);
    if (blur < minBlur) {
      return QualityGateResult(
        passed: false,
        hint: 'Too blurry — hold still',
        blurScore: blur,
        boxAreaRatio: areaRatio,
      );
    }

    // Brightness check (asleep cats OK if visible)
    final brightness = _meanLuminance(analyzed);
    if (brightness < 25) {
      return QualityGateResult(
        passed: false,
        hint: 'Too dark — find more light',
        blurScore: blur,
        boxAreaRatio: areaRatio,
      );
    }

    _recentBoxes.add(box);
    if (_recentBoxes.length > stabilityFrames) {
      _recentBoxes.removeAt(0);
    }

    if (_recentBoxes.length < stabilityFrames) {
      return QualityGateResult(
        passed: false,
        hint: 'Hold still…',
        blurScore: blur,
        boxAreaRatio: areaRatio,
      );
    }

    final stable = _isStable();
    if (!stable) {
      return QualityGateResult(
        passed: false,
        hint: 'Cat moving — wait a moment',
        blurScore: blur,
        boxAreaRatio: areaRatio,
      );
    }

    return QualityGateResult(
      passed: true,
      hint: 'Ready to scan',
      blurScore: blur,
      boxAreaRatio: areaRatio,
    );
  }

  bool _isStable() {
    if (_recentBoxes.length < 2) return false;
    for (var i = 1; i < _recentBoxes.length; i++) {
      if (_recentBoxes[i].iou(_recentBoxes[i - 1]) < minIoU) return false;
    }
    return true;
  }

  static double _meanLuminance(img.Image image) {
    var sum = 0.0;
    var n = 0;
    final stepX = math.max(1, image.width ~/ 32);
    final stepY = math.max(1, image.height ~/ 32);
    for (var y = 0; y < image.height; y += stepY) {
      for (var x = 0; x < image.width; x += stepX) {
        sum += image.getPixel(x, y).luminance;
        n++;
      }
    }
    return n == 0 ? 0 : sum / n;
  }

  /// Pick sharpest crop among candidates (burst helper).
  static img.Image pickSharpest(List<img.Image> images) {
    if (images.isEmpty) {
      throw ArgumentError('No images');
    }
    img.Image best = images.first;
    var bestScore = blurScore(best);
    for (var i = 1; i < images.length; i++) {
      final s = blurScore(images[i]);
      if (s > bestScore) {
        bestScore = s;
        best = images[i];
      }
    }
    return best;
  }
}
