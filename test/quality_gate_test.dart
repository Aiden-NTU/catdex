import 'package:catdex/ml/identity_embedder.dart';
import 'package:catdex/ml/quality_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/fixtures.dart';

void main() {
  group('QualityGate image metrics', () {
    test('blur score is deterministic, finite, and detects detail', () {
      final flat = solidImage(120);
      final detailed = checkerboardImage();

      expect(QualityGate.blurScore(flat), 0);
      expect(QualityGate.blurScore(detailed), greaterThan(0));
      expect(QualityGate.blurScore(detailed).isFinite, isTrue);
      expect(QualityGate.blurScore(detailed), QualityGate.blurScore(detailed));
    });

    test('pickSharpest returns the highest-scoring object', () {
      final flat = solidImage(120);
      final detailed = checkerboardImage();
      expect(QualityGate.pickSharpest([flat, detailed]), same(detailed));
      expect(() => QualityGate.pickSharpest([]), throwsArgumentError);
    });
  });

  group('QualityGate decisions', () {
    final detailed = checkerboardImage();

    test('rejects missing, low-confidence, small, and large detections', () {
      final gate = QualityGate(minBlur: 0);
      expect(gate.evaluate(fullFrame: detailed).hint, 'Point at a cat');
      expect(
        gate.evaluate(fullFrame: detailed, box: boxFixture(score: 0.44)).hint,
        'Point at a cat',
      );
      expect(
        gate
            .evaluate(
              fullFrame: detailed,
              box: boxFixture(right: 0.3, bottom: 0.3),
            )
            .hint,
        'Move closer',
      );
      expect(
        gate
            .evaluate(
              fullFrame: detailed,
              box: boxFixture(left: 0, top: 0, right: 1, bottom: 1),
            )
            .hint,
        'Step back a little',
      );
    });

    test('rejects blur before darkness and reports measured values', () {
      final blurry = solidImage(10);
      final blurResult = QualityGate(minBlur: 1)
          .evaluate(fullFrame: blurry, box: boxFixture());
      expect(blurResult.passed, isFalse);
      expect(blurResult.hint, contains('blurry'));
      expect(blurResult.blurScore, 0);

      final darkResult = QualityGate(minBlur: 0)
          .evaluate(fullFrame: blurry, box: boxFixture());
      expect(darkResult.passed, isFalse);
      expect(darkResult.hint, contains('dark'));
    });

    test('requires configured consecutive stable detections', () {
      final gate = QualityGate(minBlur: 1, stabilityFrames: 3, minIoU: 0.8);
      final box = boxFixture();
      final first = gate.evaluate(fullFrame: detailed, box: box);
      final second = gate.evaluate(fullFrame: detailed, box: box);
      final third = gate.evaluate(fullFrame: detailed, box: box);

      expect(first.hint, 'Hold still…');
      expect(second.hint, 'Hold still…');
      expect(third.passed, isTrue);
      expect(third.hint, 'Ready to scan');
    });

    test('reports movement and reset starts stability over', () {
      final gate = QualityGate(minBlur: 1, stabilityFrames: 2, minIoU: 0.8);
      gate.evaluate(fullFrame: detailed, box: boxFixture());
      final moved = gate.evaluate(
        fullFrame: detailed,
        box: boxFixture(left: 0.5, top: 0.5, right: 0.9, bottom: 0.9),
      );
      expect(moved.hint, 'Cat moving — wait a moment');

      gate.resetStability();
      expect(
        gate.evaluate(fullFrame: detailed, box: boxFixture()).hint,
        'Hold still…',
      );
    });
  });

  group('IdentityEmbedder', () {
    test('embedding is 128-dimensional, normalized, and deterministic', () {
      final image = img.Image(width: 80, height: 80);
      for (var y = 0; y < 80; y++) {
        for (var x = 0; x < 80; x++) {
          image.setPixelRgb(x, y, x * 2, y * 2, 100);
        }
      }

      final emb = IdentityEmbedder().embed(image);
      expect(emb, hasLength(IdentityEmbedder.dim));
      expect(
        emb.fold<double>(0, (sum, value) => sum + value * value),
        closeTo(1.0, 1e-4),
      );
      expect(IdentityEmbedder().embed(image), orderedEquals(emb));
    });

    test('grayscale has a zero opponent-color embedding', () {
      final embedding = IdentityEmbedder().embed(solidImage(127));
      expect(embedding, everyElement(0));
    });

    test('different color identities produce different embeddings', () {
      final red = img.Image(width: 16, height: 16);
      final blue = img.Image(width: 16, height: 16);
      img.fill(red, color: img.ColorRgb8(255, 0, 0));
      img.fill(blue, color: img.ColorRgb8(0, 0, 255));

      expect(
        IdentityEmbedder().embed(red),
        isNot(orderedEquals(IdentityEmbedder().embed(blue))),
      );
    });
  });

  group('DetectionBox geometry', () {
    test('exposes dimensions, area, and identical IoU', () {
      final box = boxFixture(left: 0.1, top: 0.2, right: 0.5, bottom: 0.7);
      expect(box.width, closeTo(0.4, 1e-12));
      expect(box.height, closeTo(0.5, 1e-12));
      expect(box.area, closeTo(0.2, 1e-12));
      expect(box.iou(box), closeTo(1.0, 1e-12));
    });

    test('IoU is symmetric and zero for disjoint boxes', () {
      final a = boxFixture(left: 0, top: 0, right: 0.5, bottom: 0.5);
      final b = boxFixture(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75);
      final disjoint = boxFixture(left: 0.6, top: 0.6, right: 0.9, bottom: 0.9);

      expect(a.iou(b), closeTo(1 / 7, 1e-12));
      expect(a.iou(b), closeTo(b.iou(a), 1e-12));
      expect(a.iou(disjoint), 0);
    });
  });
}
