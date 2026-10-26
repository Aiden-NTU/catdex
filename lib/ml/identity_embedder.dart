import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Compact local identity embedding (128-d) from a cat crop.
///
/// POC stand-in for a metric-learning ReID model: spatial color grid +
/// luminance histogram, L2-normalized. Same pipeline as a real embedder —
/// swap the body for a TFLite backbone later without changing callers.
class IdentityEmbedder {
  static const int dim = 128;
  static const int grid = 8; // 8x8x2 = 128 channels of mean R/B-ish + lum hist fills

  Float32List embed(img.Image crop) {
    final resized = img.copyResize(
      crop,
      width: 64,
      height: 64,
      interpolation: img.Interpolation.average,
    );

    final out = Float32List(dim);
    var idx = 0;

    // 8x8 grid of mean (r-g, b-g) → 128 values would be 8*8*2
    final cell = 64 ~/ grid;
    for (var gy = 0; gy < grid; gy++) {
      for (var gx = 0; gx < grid; gx++) {
        var sr = 0.0, sg = 0.0, sb = 0.0;
        var n = 0;
        for (var y = gy * cell; y < (gy + 1) * cell; y++) {
          for (var x = gx * cell; x < (gx + 1) * cell; x++) {
            final p = resized.getPixel(x, y);
            sr += p.r;
            sg += p.g;
            sb += p.b;
            n++;
          }
        }
        final inv = n == 0 ? 0.0 : 1.0 / n;
        final mr = sr * inv;
        final mg = sg * inv;
        final mb = sb * inv;
        // Opponent-ish channels, scaled to roughly [-1,1]
        out[idx++] = ((mr - mg) / 255.0).clamp(-1.0, 1.0);
        out[idx++] = ((mb - mg) / 255.0).clamp(-1.0, 1.0);
      }
    }

    // idx should be 128
    assert(idx == dim);

    // Light edge energy modulation so texture (fur pattern) matters
    final edge = _edgeEnergy(resized);
    for (var i = 0; i < dim; i++) {
      out[i] = out[i] * (0.85 + 0.15 * edge);
    }

    return _l2normalize(out);
  }

  double _edgeEnergy(img.Image image) {
    var sum = 0.0;
    var n = 0;
    for (var y = 1; y < image.height - 1; y += 2) {
      for (var x = 1; x < image.width - 1; x += 2) {
        final c = image.getPixel(x, y).luminance.toDouble();
        final r = image.getPixel(x + 1, y).luminance.toDouble();
        final b = image.getPixel(x, y + 1).luminance.toDouble();
        sum += (c - r).abs() + (c - b).abs();
        n++;
      }
    }
    if (n == 0) return 0.5;
    return (sum / (n * 255.0)).clamp(0.0, 1.0);
  }

  Float32List _l2normalize(Float32List v) {
    var sumSq = 0.0;
    for (final x in v) {
      sumSq += x * x;
    }
    final norm = math.sqrt(sumSq);
    if (norm < 1e-8) return v;
    final out = Float32List(v.length);
    for (var i = 0; i < v.length; i++) {
      out[i] = v[i] / norm;
    }
    return out;
  }
}
