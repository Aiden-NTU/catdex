import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'match_state.dart';

/// Client-side preview of the server's integer-only battle formula.
///
/// It is never used to decide an authoritative outcome. Keeping it byte-for-byte
/// equivalent to the Go implementation makes action previews and replays exact.
class DeterministicBattleRules {
  const DeterministicBattleRules._();

  static const abilityCost = 60;
  static const energyPerTurn = 20;

  static int damage({
    required String seed,
    required int sequence,
    required BattleCombatant actor,
    required BattleCombatant target,
    required TacticalAction action,
  }) {
    if (action == TacticalAction.guard || action == TacticalAction.surrender) {
      return 0;
    }
    final multiplier = action == TacticalAction.ability ? 135 : 100;
    final digest = sha256
        .convert(
          utf8.encode(
            '$seed\u0000$sequence\u0000${actor.cardId}\u0000${action.name}',
          ),
        )
        .bytes;
    final variation = digest[0] % 7 - 3;
    var value =
        (actor.attack * multiplier ~/ 100) - (target.defense * 35 ~/ 100);
    value = (value + variation).clamp(4, 40);
    if (target.guarding) value = ((value * 55 + 50) ~/ 100).clamp(2, 40);
    return value;
  }

  static (int min, int max) preview({
    required BattleCombatant actor,
    required BattleCombatant target,
    required TacticalAction action,
  }) {
    if (action == TacticalAction.guard || action == TacticalAction.surrender) {
      return (0, 0);
    }
    final multiplier = action == TacticalAction.ability ? 135 : 100;
    final base = actor.attack * multiplier ~/ 100 - target.defense * 35 ~/ 100;
    final reduction = target.guarding ? 55 : 100;
    int bounded(int value) {
      final raw = value.clamp(4, 40);
      return target.guarding
          ? ((raw * reduction + 50) ~/ 100).clamp(2, 40)
          : raw;
    }

    return (bounded(base - 3), bounded(base + 3));
  }
}
