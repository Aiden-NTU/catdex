import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../data/breed_catalog.dart';
import '../models/scan_result.dart';

/// Prefers Oxford-12 MobileNetV2 (`oxford_breed.tflite`); falls back to ImageNet.
class BreedClassifier {
  BreedClassifier._({
    required Interpreter interpreter,
    required List<String> labels,
    required BreedCatalog catalog,
    required bool oxfordMode,
  })  : _interpreter = interpreter,
        _labels = labels,
        _catalog = catalog,
        _oxfordMode = oxfordMode;

  final Interpreter _interpreter;
  final List<String> _labels;
  final BreedCatalog _catalog;
  final bool _oxfordMode;

  static const _inputSize = 224;
  static const _minConfidence = 0.20;

  bool get isOxfordModel => _oxfordMode;

  static Future<BreedClassifier> load(BreedCatalog catalog) async {
    final options = InterpreterOptions()..threads = 2;

    // Prefer fine-tuned Oxford breed model when bundled.
    try {
      final interpreter = await Interpreter.fromAsset(
        'assets/models/oxford_breed.tflite',
        options: options,
      );
      final raw =
          await rootBundle.loadString('assets/models/oxford_breed_labels.json');
      final labels = (jsonDecode(raw) as List).cast<String>();
      debugPrint('BreedClassifier: Oxford-12 model (${labels.length} classes)');
      return BreedClassifier._(
        interpreter: interpreter,
        labels: labels,
        catalog: catalog,
        oxfordMode: true,
      );
    } catch (e) {
      debugPrint('Oxford breed model unavailable ($e); using ImageNet fallback');
    }

    final interpreter = await Interpreter.fromAsset(
      'assets/models/mobilenet_quant.tflite',
      options: options,
    );
    final labelData =
        await rootBundle.loadString('assets/models/imagenet_labels.txt');
    final labels = labelData
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return BreedClassifier._(
      interpreter: interpreter,
      labels: labels,
      catalog: catalog,
      oxfordMode: false,
    );
  }

  BreedPrediction classify(img.Image crop) {
    final resized = img.copyResize(
      crop,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );
    final inputBytes = Uint8List(_inputSize * _inputSize * 3);
    var pi = 0;
    for (var y = 0; y < _inputSize; y++) {
      for (var x = 0; x < _inputSize; x++) {
        final p = resized.getPixel(x, y);
        inputBytes[pi++] = p.r.toInt();
        inputBytes[pi++] = p.g.toInt();
        inputBytes[pi++] = p.b.toInt();
      }
    }

    final inputTensor = _interpreter.getInputTensors().first;
    Object input;
    if (inputTensor.type == TensorType.float32) {
      // Oxford export: float32 in [0,1]
      final floats = Float32List(_inputSize * _inputSize * 3);
      for (var i = 0; i < inputBytes.length; i++) {
        floats[i] = inputBytes[i] / 255.0;
      }
      input = _reshapeFloat32(floats, _inputSize);
    } else {
      input = _reshapeUint8(inputBytes, _inputSize);
    }

    final outputTensor = _interpreter.getOutputTensors().first;
    final numClasses = outputTensor.shape.last;
    Object output;
    final isQuant = outputTensor.type == TensorType.uint8;
    if (isQuant) {
      output = List.generate(1, (_) => List<int>.filled(numClasses, 0));
    } else {
      output = List.generate(1, (_) => List<double>.filled(numClasses, 0));
    }

    try {
      _interpreter.run(input, output);
    } catch (e) {
      debugPrint('breed classify failed: $e');
      return _mixed(0.3);
    }

    final scores = <double>[];
    final row = (output as List)[0] as List;
    if (isQuant) {
      final qp = outputTensor.params;
      for (var i = 0; i < numClasses; i++) {
        scores.add(((row[i] as int) - qp.zeroPoint) * qp.scale);
      }
    } else {
      for (var i = 0; i < numClasses; i++) {
        scores.add((row[i] as num).toDouble());
      }
    }

    if (_oxfordMode) {
      return _fromOxfordScores(scores);
    }
    return _fromImageNetScores(scores);
  }

  BreedPrediction _fromOxfordScores(List<double> scores) {
    var best = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > scores[best]) best = i;
    }
    final conf = scores[best].clamp(0.0, 1.0);
    if (conf < _minConfidence || best >= _labels.length) {
      return _mixed(conf);
    }
    final info = _catalog.resolve(_labels[best]);
    return BreedPrediction(
      breedKey: info.key,
      confidence: conf,
      info: info,
    );
  }

  BreedPrediction _fromImageNetScores(List<double> scores) {
    const hints = [
      'tabby',
      'tiger cat',
      'persian cat',
      'siamese cat',
      'egyptian cat',
    ];
    var bestIdx = -1;
    var bestScore = 0.0;
    for (var i = 0; i < scores.length && i < _labels.length; i++) {
      final label = _labels[i].toLowerCase();
      final isCat = hints.any((h) => label.contains(h)) ||
          (label.contains('cat') &&
              !label.contains('cattle') &&
              !label.contains('catamaran'));
      if (!isCat) continue;
      if (scores[i] > bestScore) {
        bestScore = scores[i];
        bestIdx = i;
      }
    }
    if (bestIdx < 0 || bestScore < _minConfidence) {
      return _mixed(bestScore);
    }
    final info = _catalog.resolve(_labels[bestIdx]);
    return BreedPrediction(
      breedKey: info.key,
      confidence: bestScore,
      info: info,
    );
  }

  BreedPrediction _mixed(double conf) {
    final info = _catalog.mixed;
    return BreedPrediction(
      breedKey: info.key,
      confidence: conf.clamp(0.0, 1.0),
      info: info,
    );
  }

  List _reshapeUint8(Uint8List bytes, int size) {
    var i = 0;
    return List.generate(
      1,
      (_) => List.generate(
        size,
        (_) => List.generate(
          size,
          (_) => List.generate(3, (_) => bytes[i++]),
        ),
      ),
    );
  }

  List _reshapeFloat32(Float32List floats, int size) {
    var i = 0;
    return List.generate(
      1,
      (_) => List.generate(
        size,
        (_) => List.generate(
          size,
          (_) => List.generate(3, (_) => floats[i++]),
        ),
      ),
    );
  }

  void close() => _interpreter.close();
}
