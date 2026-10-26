import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../data/breed_catalog.dart';
import '../data/cat_repository.dart';
import '../models/scan_result.dart';
import 'breed_classifier.dart';
import 'cat_detector.dart';
import 'identity_embedder.dart';
import 'image_utils.dart';
import 'quality_gate.dart';

abstract interface class ScannerEngine {
  PreviewTick preview(img.Image frame);
  Future<ScanOutcome?> capture(img.Image frame);
  void resetGate();
  void close();
}

class ScanPipeline implements ScannerEngine {
  ScanPipeline({
    required this.detector,
    required this.classifier,
    required this.embedder,
    required this.gate,
    required this.repository,
    required this.catalog,
  });

  final CatDetector detector;
  final BreedClassifier classifier;
  final IdentityEmbedder embedder;
  final QualityGate gate;
  final CatRepository repository;
  final BreedCatalog catalog;

  bool _busy = false;

  static Future<ScanPipeline> create(CatRepository repository) async {
    final catalog = await BreedCatalog.load();
    final detector = await CatDetector.load();
    final classifier = await BreedClassifier.load(catalog);
    return ScanPipeline(
      detector: detector,
      classifier: classifier,
      embedder: IdentityEmbedder(),
      gate: QualityGate(),
      repository: repository,
      catalog: catalog,
    );
  }

  /// Live preview tick — returns gate hint + optional box for UI overlay.
  @override
  PreviewTick preview(img.Image frame) {
    final box = detector.detectBest(frame);
    img.Image? crop;
    DetectionBox? confirmed = box;
    if (box != null) {
      crop = ImageUtils.cropBox(frame, box);
      // Soft confirm: if breed model finds a feline, keep the box.
      final breed = classifier.classify(crop);
      final feline = _isFelineBreed(breed);
      if (!feline && box.score < 0.7) {
        confirmed = null;
        crop = null;
      }
    }
    final q = gate.evaluate(fullFrame: frame, box: confirmed, crop: crop);
    return PreviewTick(box: confirmed, quality: q);
  }

  /// Full capture path after user taps Scan (or auto when gate passes).
  @override
  Future<ScanOutcome?> capture(img.Image frame) async {
    if (_busy) return null;
    _busy = true;
    try {
      final box = detector.detectBest(frame);
      if (box == null) {
        debugPrint('capture: no cat');
        return null;
      }
      final crop = ImageUtils.cropBox(frame, box);
      final q = gate.evaluate(fullFrame: frame, box: box, crop: crop);
      // Allow capture even if stability not fully met when user explicitly taps,
      // but still reject blur / size / presence failures.
      if (box.score < 0.35) return null;
      if (box.area < gate.minBoxAreaRatio) return null;
      final blur = QualityGate.blurScore(crop);
      if (blur < gate.minBlur) {
        debugPrint('capture: too blurry ($blur)');
        return null;
      }

      final breed = classifier.classify(crop);
      if (!_isFelineBreed(breed)) {
        debugPrint('capture: breed model not feline (${breed.breedKey})');
        return null;
      }
      final embedding = embedder.embed(crop);
      final match = await repository.matchIdentity(embedding);

      return ScanOutcome(
        fullImage: frame,
        crop: crop,
        box: box,
        breed: breed,
        embedding: embedding,
        match: match,
        blurScore: q.blurScore > 0 ? q.blurScore : blur,
      );
    } finally {
      _busy = false;
    }
  }

  bool _isFelineBreed(BreedPrediction breed) {
    final key = breed.breedKey.toLowerCase();
    if (key.contains('mixed')) return breed.confidence >= 0.2;
    return breed.confidence >= 0.12;
  }

  @override
  void resetGate() => gate.resetStability();

  @override
  void close() {
    detector.close();
    classifier.close();
  }
}

class PreviewTick {
  const PreviewTick({required this.box, required this.quality});

  final DetectionBox? box;
  final QualityGateResult quality;
}
