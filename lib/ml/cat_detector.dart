import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/scan_result.dart';
import 'image_utils.dart';

/// COCO SSD MobileNet quantized — keeps detections whose label is `cat`.
class CatDetector {
  CatDetector._(this._interpreter, this._labels);

  final Interpreter _interpreter;
  final List<String> _labels;

  static const _inputSize = 300;
  static const _maxDetections = 10;

  static Future<CatDetector> load() async {
    final options = InterpreterOptions()..threads = 2;
    final interpreter = await Interpreter.fromAsset(
      'assets/models/detect.tflite',
      options: options,
    );
    final labelData =
        await rootBundle.loadString('assets/models/detect_labelmap.txt');
    final labels = labelData
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    debugPrint(
      'CatDetector input=${interpreter.getInputTensors()} '
      'output=${interpreter.getOutputTensors()}',
    );
    return CatDetector._(interpreter, labels);
  }

  DetectionBox? detectBest(img.Image frame) {
    final input = ImageUtils.letterboxUint8(frame, _inputSize);
    // Quantized model expects [1, 300, 300, 3] uint8
    final inputTensor = input.reshape([1, _inputSize, _inputSize, 3]);

    // SSD MobileNet outputs (TF Lite detection postprocess):
    // locations [1,10,4], classes [1,10], scores [1,10], num [1]
    final locations = List.generate(
      1,
      (_) => List.generate(10, (_) => List<double>.filled(4, 0)),
    );
    final classes = List.generate(1, (_) => List<double>.filled(10, 0));
    final scores = List.generate(1, (_) => List<double>.filled(10, 0));
    final numDetections = List<double>.filled(1, 0);

    final outputs = <int, Object>{
      0: locations,
      1: classes,
      2: scores,
      3: numDetections,
    };

    try {
      _interpreter.runForMultipleInputs([inputTensor], outputs);
    } catch (e) {
      // Some builds use different output order — try alternate mapping.
      debugPrint('detect run failed primary mapping: $e');
      return _detectFallback(frame, inputTensor);
    }

    DetectionBox? bestCat;
    DetectionBox? bestAny;
    final count = numDetections[0].toInt().clamp(0, _maxDetections);
    for (var i = 0; i < count; i++) {
      final score = scores[0][i];
      if (score < 0.35) continue;
      final classIndex = classes[0][i].toInt();
      final label =
          classIndex >= 0 && classIndex < _labels.length ? _labels[classIndex] : '';

      // locations are [ymin, xmin, ymax, xmax] in 0–1
      final loc = locations[0][i];
      final box = DetectionBox(
        top: loc[0].clamp(0.0, 1.0),
        left: loc[1].clamp(0.0, 1.0),
        bottom: loc[2].clamp(0.0, 1.0),
        right: loc[3].clamp(0.0, 1.0),
        score: score,
      );
      // SSD often confuses cats with bird/dog — keep top box for breed verify.
      final ranked = score * box.area;
      if (bestAny == null || ranked > bestAny.score * bestAny.area) {
        bestAny = box;
      }
      if (_isCatLabel(label)) {
        if (bestCat == null || box.score > bestCat.score) bestCat = box;
      }
    }
    return bestCat ?? bestAny;
  }

  DetectionBox? _detectFallback(img.Image frame, Object inputTensor) {
    // Allocate raw buffers based on tensor shapes.
    final outTensors = _interpreter.getOutputTensors();
    if (outTensors.length < 4) return null;

    final locations = List.generate(
      1,
      (_) => List.generate(10, (_) => List<double>.filled(4, 0)),
    );
    final classes = List.generate(1, (_) => List<double>.filled(10, 0));
    final scores = List.generate(1, (_) => List<double>.filled(10, 0));
    final numDetections = List<double>.filled(1, 0);

    // Common alternate order: scores, locations, num, classes — try default again
    // with float input reshaped differently if needed.
    try {
      _interpreter.runForMultipleInputs([inputTensor], {
        0: locations,
        1: classes,
        2: scores,
        3: numDetections,
      });
    } catch (_) {
      return null;
    }
    return null;
  }

  bool _isCatLabel(String label) {
    final l = label.toLowerCase();
    return l == 'cat' || l.contains('cat');
  }

  void close() => _interpreter.close();
}

extension on Uint8List {
  List reshape(List<int> shape) {
    // Nested list [1][H][W][3]
    if (shape.length != 4) {
      throw ArgumentError('Expected 4D shape');
    }
    final h = shape[1];
    final w = shape[2];
    final c = shape[3];
    var i = 0;
    return List.generate(
      shape[0],
      (_) => List.generate(
        h,
        (_) => List.generate(
          w,
          (_) => List.generate(c, (_) => this[i++]),
        ),
      ),
    );
  }
}
