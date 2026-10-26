class BreedInfo {
  const BreedInfo({
    required this.key,
    required this.displayName,
    required this.attack,
    required this.defense,
    required this.speed,
    required this.ability,
    required this.abilityDesc,
    required this.accent,
  });

  final String key;
  final String displayName;
  final int attack;
  final int defense;
  final int speed;
  final String ability;
  final String abilityDesc;
  final String accent;

  int get battlePower => attack + defense + speed;

  factory BreedInfo.fromJson(String key, Map<String, dynamic> json) {
    return BreedInfo(
      key: key,
      displayName: json['displayName'] as String,
      attack: json['attack'] as int,
      defense: json['defense'] as int,
      speed: json['speed'] as int,
      ability: json['ability'] as String,
      abilityDesc: json['abilityDesc'] as String,
      accent: json['accent'] as String,
    );
  }

  Map<String, dynamic> toStatsJson() => {
        'attack': attack,
        'defense': defense,
        'speed': speed,
        'ability': ability,
        'battlePower': battlePower,
      };
}
