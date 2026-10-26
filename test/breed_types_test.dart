import 'dart:math' as math;

import 'package:catdex/game/battle/breed_types.dart';
import 'package:catdex/game/battle/spam_battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  test('breed temper matchups follow the triangle', () {
    expect(
      BreedTypes.effectiveness(CatTemper.swift, CatTemper.trickster),
      greaterThan(1),
    );
    expect(
      BreedTypes.effectiveness(CatTemper.tank, CatTemper.brawler),
      greaterThan(1),
    );
    expect(
      BreedTypes.effectiveness(CatTemper.swift, CatTemper.brawler),
      lessThan(1),
    );
  });

  test('spam taps deal damage', () {
    final mine = catFixture(id: 'a', breed: 'Siamese', attack: 80);
    final rival = catFixture(
      id: 'b',
      breed: 'Persian',
      attack: 40,
      defense: 40,
    );
    final engine = SpamBattleEngine(
      player: mine,
      rival: rival,
      difficulty: NpcDifficulty.easy,
      random: _Fixed(),
    );
    engine.start();
    for (var i = 0; i < 25; i++) {
      engine.playerTap(DateTime.utc(2026, 1, 1).add(Duration(milliseconds: i * 60)));
    }
    expect(engine.rivalHp, lessThan(100));
    expect(engine.hits, isNotEmpty);
  });
}

class _Fixed implements math.Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0.1;

  @override
  int nextInt(int max) => 0;
}
