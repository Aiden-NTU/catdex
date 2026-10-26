import 'breed_types.dart';

enum SkillAnim { scratch, pounce, special, flurry }

class CatSkill {
  const CatSkill({
    required this.id,
    required this.name,
    required this.power,
    required this.cooldown,
    required this.anim,
    this.temperBonus,
  });

  final String id;
  final String name;
  /// Relative power (Scratch ~8, Pounce ~16, Special ~28).
  final int power;
  final Duration cooldown;
  final SkillAnim anim;
  final CatTemper? temperBonus;
}

class CatSkillKit {
  CatSkillKit._();

  static const scratch = CatSkill(
    id: 'scratch',
    name: 'Scratch',
    power: 8,
    cooldown: Duration.zero,
    anim: SkillAnim.scratch,
  );

  static const pounce = CatSkill(
    id: 'pounce',
    name: 'Pounce',
    power: 16,
    cooldown: Duration(seconds: 5),
    anim: SkillAnim.pounce,
  );

  static List<CatSkill> forBreed(String breed) {
    final temper = BreedTypes.ofBreed(breed);
    final special = switch (temper) {
      CatTemper.swift => const CatSkill(
        id: 'dash',
        name: 'Desert Dash',
        power: 26,
        cooldown: Duration(seconds: 45),
        anim: SkillAnim.flurry,
        temperBonus: CatTemper.swift,
      ),
      CatTemper.brawler => const CatSkill(
        id: 'stripe',
        name: 'Wild Stripe',
        power: 30,
        cooldown: Duration(seconds: 50),
        anim: SkillAnim.special,
        temperBonus: CatTemper.brawler,
      ),
      CatTemper.tank => const CatSkill(
        id: 'shield_bash',
        name: 'Fluff Guard',
        power: 22,
        cooldown: Duration(seconds: 40),
        anim: SkillAnim.special,
        temperBonus: CatTemper.tank,
      ),
      CatTemper.trickster => const CatSkill(
        id: 'mirage',
        name: 'Silver Mirage',
        power: 24,
        cooldown: Duration(seconds: 35),
        anim: SkillAnim.flurry,
        temperBonus: CatTemper.trickster,
      ),
      CatTemper.noble => const CatSkill(
        id: 'temple',
        name: 'Temple Strike',
        power: 28,
        cooldown: Duration(seconds: 55),
        anim: SkillAnim.special,
        temperBonus: CatTemper.noble,
      ),
    };
    return [scratch, pounce, special];
  }

  /// Highest-power skill that is currently off cooldown.
  static CatSkill? bestReady({
    required List<CatSkill> kit,
    required Map<String, DateTime> lastUsed,
    required DateTime now,
  }) {
    CatSkill? best;
    for (final skill in kit) {
      final last = lastUsed[skill.id];
      final ready = last == null ||
          now.difference(last) >= skill.cooldown;
      if (!ready) continue;
      if (best == null || skill.power > best.power) best = skill;
    }
    return best ?? scratch;
  }
}
