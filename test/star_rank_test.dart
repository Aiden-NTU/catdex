import 'dart:typed_data';

import 'package:catdex/game/star_rank.dart';
import 'package:catdex/models/breed_info.dart';
import 'package:flutter_test/flutter_test.dart';

const breed = BreedInfo(
  key: 'Siamese',
  displayName: 'Siamese',
  attack: 78,
  defense: 50,
  speed: 92,
  ability: 'Vocal Barrage',
  abilityDesc: 'x',
  accent: '#fff',
);

void main() {
  group('StarRank deterministic roll', () {
    final embedding = Float32List.fromList(
      List.generate(128, (i) => (i - 64) / 64),
    );
    final instant = DateTime.utc(2026, 6, 15, 23, 59, 59);

    test('same embedding, cell, and UTC day has a stable known result', () {
      final first = StarRank.rollStars(
        embedding: embedding,
        h3Cell: 'g_10300_-24',
        at: instant,
      );
      final second = StarRank.rollStars(
        embedding: Float32List.fromList(embedding),
        h3Cell: 'g_10300_-24',
        at: instant,
      );

      expect(first, second);
      expect(first, inInclusiveRange(1, 5));
    });

    test('all times within one UTC day use the same bucket', () {
      final morning = StarRank.rollStars(
        embedding: embedding,
        h3Cell: 'g_1_2',
        at: DateTime.utc(2026, 6, 15),
      );
      final localEquivalent = StarRank.rollStars(
        embedding: embedding,
        h3Cell: 'g_1_2',
        at: DateTime.parse('2026-06-16T00:30:00+02:00'),
      );

      expect(localEquivalent, morning);
    });

    test('roll remains within public one-to-five boundaries', () {
      final seen = <int>{};
      for (var i = 0; i < 500; i++) {
        seen.add(
          StarRank.rollStars(
            embedding: Float32List.fromList([i.toDouble(), -i.toDouble()]),
            h3Cell: 'g_${i - 250}_${i % 17}',
            at: DateTime.utc(2026, 1, (i % 28) + 1),
          ),
        );
      }

      expect(seen, everyElement(inInclusiveRange(1, 5)));
      expect(seen, containsAll(<int>[1, 2, 3, 4, 5]));
    });
  });

  group('StarRank stat boundaries', () {
    test('one and five stars use documented endpoint multipliers', () {
      expect(StarRank.multiplierFor(1), 1.0);
      expect(StarRank.multiplierFor(5), 1.48);

      final one = StarRank.apply(breed, 1);
      final five = StarRank.apply(breed, 5);
      expect(one.finalAttack, breed.attack);
      expect(one.finalDefense, breed.defense);
      expect(one.finalSpeed, breed.speed);
      expect(five.battlePower, greaterThan(one.battlePower));
      expect(
        five.battlePower,
        five.finalAttack + five.finalDefense + five.finalSpeed,
      );
    });

    test('scaled stats clamp to public 1–150 range', () {
      const extreme = BreedInfo(
        key: 'extreme',
        displayName: 'Extreme',
        attack: 0,
        defense: 200,
        speed: -10,
        ability: 'Clamp',
        abilityDesc: '',
        accent: '#000',
      );

      final roll = StarRank.apply(extreme, 5);
      expect(roll.finalAttack, 1);
      expect(roll.finalDefense, 150);
      expect(roll.finalSpeed, 1);
      expect(roll.toStatsJson(extreme)['stars'], 5);
      expect(roll.toStatsJson(extreme)['ability'], 'Clamp');
    });

    test('fromBreed composes the deterministic roll and stat application', () {
      final embedding = Float32List.fromList([0.25, -0.5, 0.75]);
      final stars = StarRank.rollStars(
        embedding: embedding,
        h3Cell: 'g_-1_2',
        at: DateTime.utc(2026, 8, 9),
      );
      final roll = StarRank.fromBreed(
        info: breed,
        embedding: embedding,
        h3Cell: 'g_-1_2',
        at: DateTime.utc(2026, 8, 9),
      );

      expect(roll.stars, stars);
      expect(roll.multiplier, StarRank.multiplierFor(stars));
    });
  });
}
