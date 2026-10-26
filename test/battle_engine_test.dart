import 'package:catdex/game/battle_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  group('BattleEngine actions', () {
    test('attack is deterministic for a seed', () {
      List<Object> run() {
        final attacker = BattleFighter(catFixture(attack: 72));
        final target = BattleFighter(catFixture(id: 'target', defense: 48));
        final engine = BattleEngine(attacker, target, seed: 17);
        engine.applyAction(attacker, target, BattleAction.attack);
        return [target.hp, ...engine.log.map((line) => line.text)];
      }

      expect(run(), run());
    });

    test(
      'defend reduces the next attack and does not damage either fighter',
      () {
        final plainAttacker = BattleFighter(catFixture(attack: 80));
        final plainTarget = BattleFighter(catFixture(id: 'plain', defense: 40));
        BattleEngine(
          plainAttacker,
          plainTarget,
          seed: 9,
        ).applyAction(plainAttacker, plainTarget, BattleAction.attack);
        final plainDamage = 100 - plainTarget.hp;

        final attacker = BattleFighter(catFixture(attack: 80));
        final target = BattleFighter(catFixture(id: 'guard', defense: 40));
        final engine = BattleEngine(attacker, target, seed: 9);
        engine.applyAction(target, attacker, BattleAction.defend);
        expect(target.defending, isTrue);
        expect(attacker.hp, 100);
        expect(target.hp, 100);

        engine.applyAction(attacker, target, BattleAction.attack);
        expect(100 - target.hp, lessThan(plainDamage));
      },
    );

    test('ability can be used once, then falls back to an attack', () {
      final actor = BattleFighter(
        catFixture(attack: 90, ability: 'Whisker Storm'),
      );
      final target = BattleFighter(catFixture(id: 'target', defense: 30));
      final engine = BattleEngine(actor, target, seed: 3);

      engine.applyAction(actor, target, BattleAction.ability);
      final hpAfterAbility = target.hp;
      expect(actor.abilityUsed, isTrue);
      expect(engine.log.last.text, contains('Whisker Storm'));

      engine.applyAction(actor, target, BattleAction.ability);
      expect(target.hp, lessThan(hpAfterAbility));
      expect(
        engine.log.map((line) => line.text),
        contains(contains('ability already used')),
      );
    });

    test('damage clamps HP at zero', () {
      final actor = BattleFighter(catFixture(attack: 150));
      final target = BattleFighter(catFixture(id: 'target', defense: 1))
        ..hp = 1;

      BattleEngine(
        actor,
        target,
        seed: 1,
      ).applyAction(actor, target, BattleAction.attack);

      expect(target.hp, 0);
      expect(target.alive, isFalse);
    });
  });

  group('BattleEngine auto battle', () {
    test('same seed and fighters produce the same complete result', () {
      BattleResult run() => BattleEngine(
        BattleFighter(catFixture(id: 'a', speed: 90)),
        BattleFighter(catFixture(id: 'b', speed: 40)),
        seed: 42,
      ).runAuto();

      final first = run();
      final second = run();
      expect(second.winnerId, first.winnerId);
      expect(second.turns, first.turns);
      expect(
        second.log.map((line) => line.text),
        first.log.map((line) => line.text),
      );
    });

    test('faster fighter acts first and max-turn ties favor fighter A', () {
      final a = BattleFighter(catFixture(id: 'a', name: 'Slow', speed: 10));
      final b = BattleFighter(catFixture(id: 'b', name: 'Fast', speed: 100));
      final result = BattleEngine(a, b, seed: 2).runAuto(maxTurns: 1);

      expect(result.turns, 1);
      expect(result.log[2].text, startsWith('Fast '));

      final tied = BattleEngine(
        BattleFighter(catFixture(id: 'a')),
        BattleFighter(catFixture(id: 'b')),
        seed: 2,
      ).runAuto(maxTurns: 0);
      expect(tied.winnerId, 'a');
      expect(tied.turns, 0);
      expect(tied.log.last.text, startsWith('Time!'));
    });
  });
}
