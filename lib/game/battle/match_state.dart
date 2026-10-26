enum TacticalAction { attack, ability, guard, surrender }

TacticalAction tacticalActionFromWire(String value) =>
    TacticalAction.values.firstWhere(
      (action) => action.name == value,
      orElse: () => TacticalAction.attack,
    );

class BattleCombatant {
  const BattleCombatant({
    required this.userId,
    required this.cardId,
    required this.name,
    required this.attack,
    required this.defense,
    required this.speed,
    required this.ability,
    this.hp = 100,
    this.energy = 0,
    this.guarding = false,
  });

  final String userId;
  final String cardId;
  final String name;
  final int attack;
  final int defense;
  final int speed;
  final String ability;
  final int hp;
  final int energy;
  final bool guarding;

  bool get alive => hp > 0;

  factory BattleCombatant.fromJson(Map<String, dynamic> json) =>
      BattleCombatant(
        userId: json['userId'] as String? ?? '',
        cardId: json['cardId'] as String? ?? '',
        name: json['name'] as String? ?? 'Cat',
        attack: (json['attack'] as num?)?.toInt() ?? 50,
        defense: (json['defense'] as num?)?.toInt() ?? 50,
        speed: (json['speed'] as num?)?.toInt() ?? 50,
        ability: json['ability'] as String? ?? 'Pounce',
        hp: (json['hp'] as num?)?.toInt() ?? 100,
        energy: (json['energy'] as num?)?.toInt() ?? 0,
        guarding: json['guarding'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'cardId': cardId,
    'name': name,
    'attack': attack,
    'defense': defense,
    'speed': speed,
    'ability': ability,
    'hp': hp,
    'energy': energy,
    'guarding': guarding,
  };

  BattleCombatant copyWith({int? hp, int? energy, bool? guarding}) =>
      BattleCombatant(
        userId: userId,
        cardId: cardId,
        name: name,
        attack: attack,
        defense: defense,
        speed: speed,
        ability: ability,
        hp: hp ?? this.hp,
        energy: energy ?? this.energy,
        guarding: guarding ?? this.guarding,
      );
}

class BattleEvent {
  const BattleEvent({
    required this.sequence,
    required this.actorCardId,
    required this.action,
    required this.damage,
    required this.targetHp,
  });

  final int sequence;
  final String actorCardId;
  final TacticalAction action;
  final int damage;
  final int targetHp;

  factory BattleEvent.fromJson(Map<String, dynamic> json) => BattleEvent(
    sequence: (json['sequence'] as num?)?.toInt() ?? 0,
    actorCardId: json['actorCardId'] as String? ?? '',
    action: tacticalActionFromWire(json['action'] as String? ?? 'attack'),
    damage: (json['damage'] as num?)?.toInt() ?? 0,
    targetHp: (json['targetHp'] as num?)?.toInt() ?? 100,
  );
}

class AuthoritativeBattleState {
  const AuthoritativeBattleState({
    required this.matchId,
    required this.revision,
    required this.turnUserId,
    required this.turnDeadline,
    required this.fighters,
    required this.events,
    required this.status,
    this.winnerUserId,
    this.localDevelopmentOpponent = false,
  });

  final String matchId;
  final int revision;
  final String turnUserId;
  final DateTime turnDeadline;
  final List<BattleCombatant> fighters;
  final List<BattleEvent> events;
  final String status;
  final String? winnerUserId;
  final bool localDevelopmentOpponent;

  bool get finished => status != 'active';

  BattleCombatant fighterForUser(String userId) =>
      fighters.firstWhere((fighter) => fighter.userId == userId);

  factory AuthoritativeBattleState.fromJson(Map<String, dynamic> json) {
    final rawFighters = json['fighters'] as List? ?? const [];
    final rawEvents = json['events'] as List? ?? const [];
    return AuthoritativeBattleState(
      matchId: json['matchId'] as String? ?? '',
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      turnUserId: json['turnUserId'] as String? ?? '',
      turnDeadline:
          DateTime.tryParse(json['turnDeadline'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      fighters: rawFighters
          .whereType<Map>()
          .map(
            (value) => BattleCombatant.fromJson(value.cast<String, dynamic>()),
          )
          .toList(growable: false),
      events: rawEvents
          .whereType<Map>()
          .map((value) => BattleEvent.fromJson(value.cast<String, dynamic>()))
          .toList(growable: false),
      status: json['status'] as String? ?? 'active',
      winnerUserId: json['winnerUserId'] as String?,
      localDevelopmentOpponent:
          json['localDevelopmentOpponent'] as bool? ?? false,
    );
  }
}
