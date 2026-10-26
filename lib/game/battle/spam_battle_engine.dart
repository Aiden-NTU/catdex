import 'dart:math' as math;

import '../../models/cat.dart';
import 'breed_types.dart';
import 'cat_skills.dart';

enum SpamPhase { intro, playerWindow, npcWindow, victory, defeat }

enum NpcDifficulty { easy, normal, hard }

class SpamHit {
  SpamHit({
    required this.actorIsPlayer,
    required this.skill,
    required this.damage,
    required this.crit,
    required this.effectiveness,
    required this.at,
  });

  final bool actorIsPlayer;
  final CatSkill skill;
  final int damage;
  final bool crit;
  final double effectiveness;
  final DateTime at;
}

/// Local spam-tap duel for map encounters — not Nakama PvP.
class SpamBattleEngine {
  SpamBattleEngine({
    required this.player,
    required this.rival,
    this.difficulty = NpcDifficulty.normal,
    this.window = const Duration(seconds: 8),
    math.Random? random,
  }) : _rng = random ?? math.Random(),
       playerTemper = BreedTypes.ofBreed(player.breed),
       rivalTemper = BreedTypes.ofBreed(rival.breed),
       playerKit = CatSkillKit.forBreed(player.breed),
       rivalKit = CatSkillKit.forBreed(rival.breed),
       playerHp = 100,
       rivalHp = 100;

  final CollectedCat player;
  final CollectedCat rival;
  final NpcDifficulty difficulty;
  final Duration window;
  final math.Random _rng;

  final CatTemper playerTemper;
  final CatTemper rivalTemper;
  final List<CatSkill> playerKit;
  final List<CatSkill> rivalKit;

  int playerHp;
  int rivalHp;
  SpamPhase phase = SpamPhase.intro;
  DateTime? windowEnds;
  final lastUsedPlayer = <String, DateTime>{};
  final lastUsedRival = <String, DateTime>{};
  final hits = <SpamHit>[];
  int tapsThisWindow = 0;
  DateTime? _lastTap;

  bool get finished =>
      phase == SpamPhase.victory || phase == SpamPhase.defeat;

  void start() {
    phase = SpamPhase.playerWindow;
    windowEnds = DateTime.now().add(window);
    tapsThisWindow = 0;
  }

  /// Player spam-tap on the rival card.
  SpamHit? playerTap(DateTime now) {
    if (phase != SpamPhase.playerWindow || finished) return null;
    if (windowEnds != null && now.isAfter(windowEnds!)) {
      _beginNpc(now);
      return null;
    }

    final skill = CatSkillKit.bestReady(
      kit: playerKit,
      lastUsed: lastUsedPlayer,
      now: now,
    )!;
    lastUsedPlayer[skill.id] = now;
    tapsThisWindow++;

    var critChance = 0.08;
    if (_lastTap != null && now.difference(_lastTap!) < const Duration(milliseconds: 180)) {
      critChance += 0.12; // PoGo-style rapid tap bonus
    }
    if (tapsThisWindow > 8) critChance += 0.05;
    _lastTap = now;
    final crit = _rng.nextDouble() < critChance;

    final eff = BreedTypes.effectiveness(playerTemper, rivalTemper);
    final damage = _rollDamage(
      skill: skill,
      attackerAtk: player.attack,
      defenderDef: rival.defense,
      effectiveness: eff,
      crit: crit,
    );
    rivalHp = (rivalHp - damage).clamp(0, 100);
    final hit = SpamHit(
      actorIsPlayer: true,
      skill: skill,
      damage: damage,
      crit: crit,
      effectiveness: eff,
      at: now,
    );
    hits.add(hit);
    if (rivalHp <= 0) {
      phase = SpamPhase.victory;
      return hit;
    }
    return hit;
  }

  void tick(DateTime now) {
    if (finished) return;
    if (phase == SpamPhase.playerWindow &&
        windowEnds != null &&
        now.isAfter(windowEnds!)) {
      _beginNpc(now);
    } else if (phase == SpamPhase.npcWindow &&
        windowEnds != null &&
        now.isAfter(windowEnds!)) {
      phase = SpamPhase.playerWindow;
      windowEnds = now.add(window);
      tapsThisWindow = 0;
    }
  }

  void _beginNpc(DateTime now) {
    phase = SpamPhase.npcWindow;
    final npcDuration = switch (difficulty) {
      NpcDifficulty.easy => const Duration(seconds: 4),
      NpcDifficulty.normal => const Duration(seconds: 5),
      NpcDifficulty.hard => const Duration(seconds: 6),
    };
    windowEnds = now.add(npcDuration);
    _runNpcBurst(now);
  }

  void _runNpcBurst(DateTime now) {
    final taps = switch (difficulty) {
      NpcDifficulty.easy => 2 + _rng.nextInt(2),
      NpcDifficulty.normal => 3 + _rng.nextInt(3),
      NpcDifficulty.hard => 5 + _rng.nextInt(3),
    };
    for (var i = 0; i < taps; i++) {
      if (playerHp <= 0) break;
      final skill = _npcPickSkill(now);
      lastUsedRival[skill.id] = now;
      final eff = BreedTypes.effectiveness(rivalTemper, playerTemper);
      final crit = _rng.nextDouble() <
          (difficulty == NpcDifficulty.hard ? 0.18 : 0.08);
      final damage = _rollDamage(
        skill: skill,
        attackerAtk: rival.attack,
        defenderDef: player.defense,
        effectiveness: eff,
        crit: crit,
      );
      playerHp = (playerHp - damage).clamp(0, 100);
      hits.add(
        SpamHit(
          actorIsPlayer: false,
          skill: skill,
          damage: damage,
          crit: crit,
          effectiveness: eff,
          at: now,
        ),
      );
    }
    if (playerHp <= 0) phase = SpamPhase.defeat;
  }

  CatSkill _npcPickSkill(DateTime now) {
    final ready = rivalKit.where((s) {
      final last = lastUsedRival[s.id];
      return last == null || now.difference(last) >= s.cooldown;
    }).toList();
    if (ready.isEmpty) return CatSkillKit.scratch;

    // Prefer skills that are strong into the player's temper.
    ready.sort((a, b) {
      final ea = a.temperBonus == null
          ? 1.0
          : BreedTypes.effectiveness(a.temperBonus!, playerTemper);
      final eb = b.temperBonus == null
          ? 1.0
          : BreedTypes.effectiveness(b.temperBonus!, playerTemper);
      final scoreA = a.power * ea;
      final scoreB = b.power * eb;
      return scoreB.compareTo(scoreA);
    });

    return switch (difficulty) {
      NpcDifficulty.easy => ready[_rng.nextInt(ready.length)],
      NpcDifficulty.normal =>
        _rng.nextDouble() < 0.65 ? ready.first : ready[_rng.nextInt(ready.length)],
      NpcDifficulty.hard => ready.first,
    };
  }

  int _rollDamage({
    required CatSkill skill,
    required int attackerAtk,
    required int defenderDef,
    required double effectiveness,
    required bool crit,
  }) {
    var value =
        (skill.power + attackerAtk * skill.power ~/ 100) -
        (defenderDef * 12 ~/ 100);
    value = (value * effectiveness).round();
    if (crit) value = (value * 1.5).round();
    return value.clamp(2, 42);
  }
}
