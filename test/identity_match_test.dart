import 'dart:typed_data';

import 'package:catdex/data/cat_repository.dart';
import 'package:catdex/models/cat.dart';
import 'package:catdex/models/scan_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('identity cosine similarity', () {
    test(
      'identical, scaled, orthogonal, and opposite vectors hit boundaries',
      () {
        final vector = Float32List.fromList([3, 4]);
        expect(
          CatRepository.cosineSimilarity(vector, vector),
          closeTo(1, 1e-12),
        );
        expect(
          CatRepository.cosineSimilarity(vector, Float32List.fromList([6, 8])),
          closeTo(1, 1e-12),
        );
        expect(
          CatRepository.cosineSimilarity(
            Float32List.fromList([1, 0]),
            Float32List.fromList([0, 1]),
          ),
          closeTo(0, 1e-12),
        );
        expect(
          CatRepository.cosineSimilarity(
            Float32List.fromList([1, 0]),
            Float32List.fromList([-1, 0]),
          ),
          closeTo(-1, 1e-12),
        );
      },
    );

    test('zero and empty vectors return zero without NaN', () {
      expect(
        CatRepository.cosineSimilarity(
          Float32List(3),
          Float32List.fromList([1, 2, 3]),
        ),
        0,
      );
      expect(CatRepository.cosineSimilarity(Float32List(0), Float32List(0)), 0);
    });

    test('mismatched lengths consistently compare the shared prefix', () {
      final short = Float32List.fromList([1, 2]);
      final long = Float32List.fromList([1, 2, 100]);
      expect(CatRepository.cosineSimilarity(short, long), closeTo(1, 1e-12));
      expect(
        CatRepository.cosineSimilarity(short, long),
        CatRepository.cosineSimilarity(long, short),
      );
    });
  });

  test('identity result preserves decision, score, and matched cat', () {
    final cat = CollectedCat(
      id: 'cat-1',
      name: 'Mochi',
      breed: 'Mixed',
      breedConfidence: 0.8,
      embedding: Float32List.fromList([1, 0]),
      createdAt: DateTime.utc(2026),
      statsJson: '{}',
    );
    final match = IdentityMatch(
      decision: MatchDecision.duplicate,
      bestSimilarity: 0.95,
      matchedCat: cat,
    );

    expect(match.decision, MatchDecision.duplicate);
    expect(match.bestSimilarity, 0.95);
    expect(match.matchedCat, same(cat));
  });
}
