import 'package:catdex/game/battle/deterministic_rules.dart';
import 'package:catdex/game/battle/match_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const actor = BattleCombatant(
    userId: 'u1',
    cardId: 'miso',
    name: 'Miso',
    attack: 45,
    defense: 40,
    speed: 70,
    ability: 'Whisker Storm',
    energy: 100,
  );
  const target = BattleCombatant(
    userId: 'u2',
    cardId: 'bean',
    name: 'Bean',
    attack: 40,
    defense: 50,
    speed: 60,
    ability: 'Pounce',
  );

  test('Dart matches Go integer-only golden vectors', () {
    expect(
      DeterministicBattleRules.damage(
        seed: 'golden',
        sequence: 1,
        actor: actor,
        target: target,
        action: TacticalAction.attack,
      ),
      26,
    );
    expect(
      DeterministicBattleRules.damage(
        seed: 'golden',
        sequence: 2,
        actor: actor,
        target: target,
        action: TacticalAction.ability,
      ),
      40,
    );
  });

  test('guard preview and resolved damage use the same rounding', () {
    final guarded = target.copyWith(guarding: true);
    final preview = DeterministicBattleRules.preview(
      actor: actor,
      target: guarded,
      action: TacticalAction.attack,
    );
    final damage = DeterministicBattleRules.damage(
      seed: 'golden',
      sequence: 1,
      actor: actor,
      target: guarded,
      action: TacticalAction.attack,
    );
    expect(damage, inInclusiveRange(preview.$1, preview.$2));
    expect(damage, 14);
  });
}
