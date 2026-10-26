import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import 'breed_info.dart';
import 'cat.dart';

enum MatchDecision { unique, duplicate, ambiguous }

class DetectionBox {
  const DetectionBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.score,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
  final double score;

  double get width => right - left;
  double get height => bottom - top;
  double get area => width * height;

  Rect get rect => Rect.fromLTRB(left, top, right, bottom);

  double iou(DetectionBox other) {
    final x1 = left > other.left ? left : other.left;
    final y1 = top > other.top ? top : other.top;
    final x2 = right < other.right ? right : other.right;
    final y2 = bottom < other.bottom ? bottom : other.bottom;
    final interW = x2 - x1;
    final interH = y2 - y1;
    if (interW <= 0 || interH <= 0) return 0;
    final inter = interW * interH;
    return inter / (area + other.area - inter);
  }
}

class QualityGateResult {
  const QualityGateResult({
    required this.passed,
    required this.hint,
    this.blurScore = 0,
    this.boxAreaRatio = 0,
  });

  final bool passed;
  final String hint;
  final double blurScore;
  final double boxAreaRatio;
}

class BreedPrediction {
  const BreedPrediction({
    required this.breedKey,
    required this.confidence,
    required this.info,
  });

  final String breedKey;
  final double confidence;
  final BreedInfo info;
}

class IdentityMatch {
  const IdentityMatch({
    required this.decision,
    required this.bestSimilarity,
    this.matchedCat,
  });

  final MatchDecision decision;
  final double bestSimilarity;
  final CollectedCat? matchedCat;
}

class ScanOutcome {
  ScanOutcome({
    required this.fullImage,
    required this.crop,
    required this.box,
    required this.breed,
    required this.embedding,
    required this.match,
    required this.blurScore,
  });

  final img.Image fullImage;
  final img.Image crop;
  final DetectionBox box;
  final BreedPrediction breed;
  final Float32List embedding;
  final IdentityMatch match;
  final double blurScore;
}
