import 'dart:math';

import '../models/cat.dart';

enum BattleAction { attack, defend, ability }

class BattleFighter {
  BattleFighter(CollectedCat cat)
      : id = cat.id,
        name = cat.name,
        breed = cat.breed,
        stars = cat.stars,
        attack = cat.attack,
        defense = cat.defense,
        speed = cat.speed,
        ability = cat.ability,
        hp = 100,
        abilityUsed = false;

  final String id;
  final String name;
  final String breed;
  final int stars;
  final int attack;
  final int defense;
  final int speed;
  final String ability;
  int hp;
  bool abilityUsed;
  bool defending = false;

  bool get alive => hp > 0;
}

class BattleLogLine {
  BattleLogLine(this.text, {this.highlight = false});
  final String text;
  final bool highlight;
}

class BattleResult {
  BattleResult({
    required this.winnerId,
    required this.log,
    required this.turns,
  });
  final String winnerId;
  final List<BattleLogLine> log;
  final int turns;
}

/// Local authoritative-style turn engine (also mirrors server rules).
class BattleEngine {
  BattleEngine(this.a, this.b, {int? seed}) : _rng = Random(seed);

  final BattleFighter a;
  final BattleFighter b;
  final Random _rng;
  final log = <BattleLogLine>[];

  BattleResult runAuto({int maxTurns = 12}) {
    log.add(BattleLogLine(
      '${a.name} (${a.stars}★) vs ${b.name} (${b.stars}★)!',
      highlight: true,
    ));
    var turn = 0;
    while (a.alive && b.alive && turn < maxTurns) {
      turn++;
      final first = a.speed >= b.speed ? a : b;
      final second = identical(first, a) ? b : a;
      _takeTurn(first, second, turn);
      if (!second.alive) break;
      _takeTurn(second, first, turn);
    }
    if (a.alive && b.alive) {
      final winner = a.hp >= b.hp ? a : b;
      log.add(BattleLogLine(
        'Time! ${winner.name} wins on remaining HP.',
        highlight: true,
      ));
      return BattleResult(winnerId: winner.id, log: log, turns: turn);
    }
    final winner = a.alive ? a : b;
    log.add(BattleLogLine('${winner.name} wins!', highlight: true));
    return BattleResult(winnerId: winner.id, log: log, turns: turn);
  }

  /// Interactive: apply one chosen action for [actor] against [target].
  void applyAction(BattleFighter actor, BattleFighter target, BattleAction action) {
    actor.defending = false;
    switch (action) {
      case BattleAction.defend:
        actor.defending = true;
        log.add(BattleLogLine('${actor.name} braces (defense up).'));
      case BattleAction.ability:
        if (actor.abilityUsed) {
          log.add(BattleLogLine('${actor.name} ability already used — attacks instead.'));
          _attack(actor, target);
        } else {
          actor.abilityUsed = true;
          final bonus = 1.35 + _rng.nextDouble() * 0.25;
          final dmg = _damage(actor, target, bonus);
          target.hp = (target.hp - dmg).clamp(0, 100);
          log.add(BattleLogLine(
            '${actor.name} uses ${actor.ability}! $dmg dmg.',
            highlight: true,
          ));
        }
      case BattleAction.attack:
        _attack(actor, target);
    }
  }

  void _takeTurn(BattleFighter actor, BattleFighter target, int turn) {
    // AI: ability once if HP advantage low, else attack/defend
    BattleAction action;
    if (!actor.abilityUsed && actor.hp < 55 && _rng.nextDouble() < 0.55) {
      action = BattleAction.ability;
    } else if (_rng.nextDouble() < 0.18) {
      action = BattleAction.defend;
    } else {
      action = BattleAction.attack;
    }
    log.add(BattleLogLine('— Turn $turn —'));
    applyAction(actor, target, action);
  }

  void _attack(BattleFighter actor, BattleFighter target) {
    final dmg = _damage(actor, target, 1.0);
    target.hp = (target.hp - dmg).clamp(0, 100);
    log.add(BattleLogLine('${actor.name} attacks for $dmg. (${target.name} HP ${target.hp})'));
  }

  int _damage(BattleFighter actor, BattleFighter target, double mult) {
    final raw = actor.attack * mult - target.defense * 0.35;
    var dmg = raw.round().clamp(4, 40);
    if (target.defending) dmg = (dmg * 0.55).round().clamp(2, 40);
    // crit
    if (_rng.nextDouble() < 0.08 + actor.stars * 0.01) {
      dmg = (dmg * 1.5).round();
      log.add(BattleLogLine('Critical hit!', highlight: true));
    }
    return dmg;
  }
}
