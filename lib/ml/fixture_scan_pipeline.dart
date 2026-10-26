import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../data/breed_catalog.dart';
import '../data/cat_repository.dart';
import '../models/scan_result.dart';
import 'scan_pipeline.dart';

/// Model-free scanner used only by the explicitly enabled desktop simulator.
class FixtureScanPipeline implements ScannerEngine {
  FixtureScanPipeline._(this._repository, this._catalog);

  final CatRepository _repository;
  final BreedCatalog _catalog;
  bool _closed = false;

  static Future<FixtureScanPipeline> create(CatRepository repository) async =>
      FixtureScanPipeline._(repository, await BreedCatalog.load());

  static const _box = DetectionBox(
    left: .14,
    top: .1,
    right: .86,
    bottom: .92,
    score: .99,
  );

  @override
  PreviewTick preview(img.Image frame) {
    _checkOpen();
    return const PreviewTick(
      box: _box,
      quality: QualityGateResult(
        passed: true,
        hint: 'Fixture cat ready (simulator)',
        blurScore: 100,
        boxAreaRatio: .59,
      ),
    );
  }

  @override
  Future<ScanOutcome?> capture(img.Image frame) async {
    _checkOpen();
    final crop = img.copyCrop(
      frame,
      x: (frame.width * _box.left).round(),
      y: (frame.height * _box.top).round(),
      width: (frame.width * _box.width).round(),
      height: (frame.height * _box.height).round(),
    );
    final embedding = Float32List(128);
    for (var i = 0; i < embedding.length; i++) {
      embedding[i] = ((i % 17) - 8) / 64;
    }
    return ScanOutcome(
      fullImage: frame,
      crop: crop,
      box: _box,
      breed: BreedPrediction(
        breedKey: _catalog.mixed.key,
        confidence: .96,
        info: _catalog.mixed,
      ),
      embedding: embedding,
      match: await _repository.matchIdentity(embedding),
      blurScore: 100,
    );
  }

  @override
  void resetGate() {}

  @override
  void close() => _closed = true;

  void _checkOpen() {
    if (_closed) throw StateError('Scanner has been closed');
  }
}
