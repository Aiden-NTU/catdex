/// Elemental “temper” for breed matchups (Pokémon-style triangle + neutrals).
enum CatTemper { swift, brawler, tank, trickster, noble }

extension CatTemperLabel on CatTemper {
  String get label => switch (this) {
    CatTemper.swift => 'Swift',
    CatTemper.brawler => 'Brawler',
    CatTemper.tank => 'Tank',
    CatTemper.trickster => 'Trickster',
    CatTemper.noble => 'Noble',
  };
}

class BreedTypes {
  BreedTypes._();

  static CatTemper ofBreed(String breed) {
    final key = breed.toLowerCase();
    if (key.contains('abyssinian') ||
        key.contains('egyptian') ||
        key.contains('siamese') ||
        key.contains('mau')) {
      return CatTemper.swift;
    }
    if (key.contains('bengal') ||
        key.contains('bombay') ||
        key.contains('sphynx')) {
      return CatTemper.brawler;
    }
    if (key.contains('british') ||
        key.contains('maine') ||
        key.contains('persian')) {
      return CatTemper.tank;
    }
    if (key.contains('ragdoll') ||
        key.contains('russian') ||
        key.contains('mixed')) {
      return CatTemper.trickster;
    }
    if (key.contains('birman')) return CatTemper.noble;
    return CatTemper.trickster;
  }

  /// 1.0 neutral, 1.35 strong, 0.7 weak.
  static double effectiveness(CatTemper attacker, CatTemper defender) {
    if (attacker == defender) return 1.0;
    // Swift > Trickster > Tank > Brawler > Swift
    // Noble beats Trickster, loses to Brawler, else neutral-ish
    const strong = <(CatTemper, CatTemper)>{
      (CatTemper.swift, CatTemper.trickster),
      (CatTemper.trickster, CatTemper.tank),
      (CatTemper.tank, CatTemper.brawler),
      (CatTemper.brawler, CatTemper.swift),
      (CatTemper.noble, CatTemper.trickster),
      (CatTemper.brawler, CatTemper.noble),
    };
    const weak = <(CatTemper, CatTemper)>{
      (CatTemper.trickster, CatTemper.swift),
      (CatTemper.tank, CatTemper.trickster),
      (CatTemper.brawler, CatTemper.tank),
      (CatTemper.swift, CatTemper.brawler),
      (CatTemper.trickster, CatTemper.noble),
      (CatTemper.noble, CatTemper.brawler),
    };
    if (strong.contains((attacker, defender))) return 1.35;
    if (weak.contains((attacker, defender))) return 0.7;
    return 1.0;
  }

  static String tip(CatTemper a, CatTemper d) {
    final m = effectiveness(a, d);
    if (m > 1.1) return 'Super effective!';
    if (m < 0.9) return 'Not very effective…';
    return 'Neutral';
  }
}
