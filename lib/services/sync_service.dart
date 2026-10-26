import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/nakama_config.dart';
import '../data/cat_repository.dart';
import '../game/battle/deterministic_rules.dart';
import '../game/battle/match_state.dart';
import '../models/cat.dart';
import 'nakama_client.dart';

class SyncService {
  SyncService(this.repository, {this.client, NakamaConfig? config})
    : config = config ?? NakamaConfig.fromEnvironment();

  final CatRepository repository;
  final NakamaConfig config;
  final NakamaClient? client;
  NakamaClient? _createdClient;
  final Map<String, AuthoritativeBattleState> _developmentBattles = {};

  Future<String> deviceUserId() async {
    return (await _nakama()).deviceId();
  }

  Future<bool> nakamaReachable() async {
    return (await _nakama()).healthcheck();
  }

  Future<String> pushInventory() async {
    final cats = await repository.getAll();
    final cards = cats.map((cat) => cat.toSyncJson()).toList();
    final mirror = jsonEncode({
      'updatedAt': DateTime.now().toIso8601String(),
      'cards': cards,
    });
    try {
      final client = await _nakama();
      final replayed = await client.flushOutbox();
      final upserted = await client.upsertInventory(cards);
      if (config.developmentMode) await _saveMirror(mirror);
      return 'Synced $upserted cards'
          '${replayed == 0 ? '' : ' ($replayed queued operations replayed)'}';
    } on NakamaQueuedException {
      if (config.developmentMode) await _saveMirror(mirror);
      return 'Queued ${cats.length} cards for sync';
    } on NakamaException {
      if (!config.developmentMode) rethrow;
      await _saveMirror(mirror);
      return 'Saved ${cats.length} cards to development mirror';
    }
  }

  Future<List<Map<String, dynamic>>> pullMirrorCards() async {
    try {
      final inventory = await (await _nakama()).getInventory();
      for (final card in inventory.cards) {
        await repository.applyServerCard(card.json);
      }
      return inventory.cards.map((card) => card.json).toList();
    } on NakamaException {
      if (!config.developmentMode) rethrow;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cloud_bag_mirror');
    if (raw == null) return [];
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final cards = map['cards'] as List? ?? [];
    return cards.cast<Map<String, dynamic>>();
  }

  /// Real matchmaking only. Returns null when nobody is available.
  Future<CollectedCat?> ghostOpponent(CollectedCat mine) async {
    try {
      final opponent = await (await _nakama()).getOpponent(
        cardId: mine.id,
        h3Cell: mine.h3Cell == 'unknown' ? null : mine.h3Cell,
      );
      return _fromSync(opponent.json);
    } on Object {
      return null;
    }
  }

  /// Scripted map encounters — local rules, not pretended PvP.
  bool isNpcEncounter(CollectedCat opponent) =>
      opponent.id.startsWith('npc-') ||
      opponent.id.startsWith('enc-') ||
      opponent.id.startsWith('street-rival-');

  Future<NakamaInventory> getInventory() async =>
      (await _nakama()).getInventory();

  Future<NakamaEnrollResult> enroll({
    required String fingerprint,
    required String name,
    required String breed,
    required double breedConfidence,
    required String h3Cell,
    required double lat,
    required double lng,
    required double accuracyM,
    required DateTime capturedAt,
    required int baseAttack,
    required int baseDefense,
    required int baseSpeed,
    String ability = '',
    String accentColor = '',
    String? requestId,
  }) async {
    return (await _nakama()).enroll(
      fingerprint: fingerprint,
      name: name,
      breed: breed,
      breedConfidence: breedConfidence,
      h3Cell: h3Cell,
      lat: lat,
      lng: lng,
      accuracyM: accuracyM,
      capturedAt: capturedAt,
      baseAttack: baseAttack,
      baseDefense: baseDefense,
      baseSpeed: baseSpeed,
      ability: ability,
      accentColor: accentColor,
      requestId: requestId,
    );
  }

  Future<NakamaFeedResult> feed({
    required String cardId,
    required int amount,
    String? requestId,
  }) async => (await _nakama()).feed(
    cardId: cardId,
    amount: amount,
    requestId: requestId,
  );

  Future<NakamaCareState> getCareState(String cardId) async {
    try {
      final state = await (await _nakama()).getCareState(cardId);
      await _cacheCareState(state);
      return state;
    } on NakamaException {
      if (!config.developmentMode) rethrow;
      return _developmentCareState(cardId);
    }
  }

  Future<NakamaCareState> careAction({
    required String cardId,
    required String action,
    String? requestId,
  }) async {
    try {
      final state = await (await _nakama()).careAction(
        cardId: cardId,
        action: action,
        requestId: requestId,
      );
      await _cacheCareState(state);
      return state;
    } on NakamaException {
      if (!config.developmentMode) rethrow;
      return _developmentCareAction(cardId, action);
    }
  }

  Future<void> _cacheCareState(NakamaCareState state) async {
    await repository.applyServerCard(state.card.json);
    await repository.updateAccountCache(state.account.json);
  }

  Future<NakamaCareState> _developmentCareState(String cardId) async {
    final cat = await repository.getById(cardId);
    if (cat == null) throw const NakamaException('Cat not found');
    final account = await repository.getAccountCache();
    return NakamaCareState(
      card: NakamaCard(_catCareJson(cat)),
      account: NakamaCareAccount({
        'pawCoins': account.pawCoins,
        'dailyEarned': account.dailyEarned,
        'dailyCap': account.dailyCap,
        'treats': account.treats == 0 ? 5 : account.treats,
        'groomingSupplies': account.groomingSupplies == 0
            ? 3
            : account.groomingSupplies,
      }),
    );
  }

  Future<NakamaCareState> _developmentCareAction(
    String cardId,
    String action,
  ) async {
    final current = await _developmentCareState(cardId);
    final card = Map<String, dynamic>.of(current.card.json);
    final account = Map<String, dynamic>.of(current.account.json);
    const xp = {'feed': 15, 'play': 20, 'groom': 20, 'train': 30, 'rest': 0};
    const coins = {'feed': 2, 'play': 3, 'groom': 3, 'train': 4, 'rest': 0};
    void bump(String key, int amount) {
      card[key] = (((card[key] as num?)?.toInt() ?? 0) + amount).clamp(0, 100);
    }

    switch (action) {
      case 'feed':
        bump('hunger', 20);
        bump('mood', 5);
        bump('bond', 10);
        break;
      case 'play':
        bump('energy', -15);
        bump('mood', 15);
        bump('bond', 8);
        break;
      case 'groom':
        bump('mood', 10);
        bump('bond', 12);
        break;
      case 'train':
        bump('energy', -20);
        bump('bond', 5);
        bump('abilityMastery', 10);
        break;
      case 'rest':
        bump('energy', 30);
        bump('mood', 3);
        break;
      default:
        throw const NakamaException('Unknown care action');
    }
    card['xp'] = ((card['xp'] as num?)?.toInt() ?? 0) + (xp[action] ?? 0);
    card['progressionUpdatedAt'] = DateTime.now().toUtc().toIso8601String();
    final room = (account['dailyCap'] as num?)?.toInt() ?? 100;
    final earned = (account['dailyEarned'] as num?)?.toInt() ?? 0;
    final coinAward = (coins[action] ?? 0).clamp(0, room - earned);
    account['pawCoins'] =
        ((account['pawCoins'] as num?)?.toInt() ?? 0) + coinAward;
    account['dailyEarned'] = earned + coinAward;
    final state = NakamaCareState(
      card: NakamaCard(card),
      account: NakamaCareAccount(account),
      action: action,
      xpAwarded: xp[action] ?? 0,
      coinsAwarded: coinAward,
    );
    await _cacheCareState(state);
    return state;
  }

  Map<String, dynamic> _catCareJson(CollectedCat cat) => {
    ...cat.toSyncJson(),
    'level': cat.level,
    'xp': cat.xp,
    'energy': cat.energy,
    'hunger': cat.hunger,
    'mood': cat.mood,
    'bond': cat.bond,
    'abilityMastery': cat.abilityMastery,
  };

  Future<List<NakamaEvent>> nearbyEvents(List<String> h3Cells) async =>
      (await _nakama()).nearbyEvents(h3Cells);

  Future<NakamaContributionResult> contributeEvent({
    required String eventId,
    required int amount,
    required String h3Cell,
    required double lat,
    required double lng,
    required double accuracyM,
    required String type,
    String squadId = '',
    String checkpointId = '',
    bool stationary = false,
    String? requestId,
  }) async => (await _nakama()).contributeEvent(
    eventId: eventId,
    amount: amount,
    h3Cell: h3Cell,
    lat: lat,
    lng: lng,
    accuracyM: accuracyM,
    type: type,
    squadId: squadId,
    checkpointId: checkpointId,
    stationary: stationary,
    requestId: requestId,
  );

  Future<Map<String, dynamic>> eventSummary(String eventId) async =>
      (await _nakama()).eventSummary(eventId);

  Future<NakamaBattleResult> resolveBattle({
    required String cardId,
    required String opponentCardId,
    String? requestId,
  }) async => (await _nakama()).resolveBattle(
    cardId: cardId,
    opponentCardId: opponentCardId,
    requestId: requestId,
  );

  Future<AuthoritativeBattleState> startBattle({
    required CollectedCat mine,
    required CollectedCat opponent,
  }) async {
    // Scripted map encounters run locally; they are not pretended to be PvP.
    if (isNpcEncounter(opponent)) {
      return _startLocalNpcBattle(mine, opponent);
    }
    return (await (await _nakama()).startBattle(
      cardId: mine.id,
      opponentCardId: opponent.id,
      localDevelopmentOpponent: false,
    )).state;
  }

  Future<AuthoritativeBattleState> getBattle({
    required String matchId,
    required String cardId,
  }) async {
    if (matchId.startsWith('npc-') || matchId.startsWith('local-')) {
      final state = _developmentBattles[matchId];
      if (state == null) throw const NakamaException('NPC battle not found');
      return state;
    }
    return (await (await _nakama()).getBattle(
      matchId: matchId,
      cardId: cardId,
    )).state;
  }

  Future<AuthoritativeBattleState> submitBattleAction({
    required String matchId,
    required int expectedRevision,
    required TacticalAction action,
  }) async {
    if (matchId.startsWith('npc-') || matchId.startsWith('local-')) {
      return _developmentAction(matchId, expectedRevision, action);
    }
    return (await (await _nakama()).submitBattleAction(
      matchId: matchId,
      expectedRevision: expectedRevision,
      action: action,
    )).state;
  }

  Future<NakamaClient> _nakama() async {
    final existing = client ?? _createdClient;
    if (existing != null) return existing;
    final created = NakamaClient(
      config: config,
      preferences: await SharedPreferences.getInstance(),
    );
    _createdClient = created;
    return created;
  }

  Future<AuthoritativeBattleState> _startLocalNpcBattle(
    CollectedCat mine,
    CollectedCat opponent,
  ) async {
    final matchId = 'npc-${DateTime.now().microsecondsSinceEpoch}';
    BattleCombatant fighter(CollectedCat cat, String userId) => BattleCombatant(
      userId: userId,
      cardId: cat.id,
      name: cat.name,
      attack: cat.attack,
      defense: cat.defense,
      speed: cat.speed,
      ability: cat.ability,
    );
    final state = AuthoritativeBattleState(
      matchId: matchId,
      revision: 0,
      turnUserId: 'local-player',
      turnDeadline: DateTime.now().toUtc().add(const Duration(seconds: 30)),
      fighters: [
        fighter(mine, 'local-player'),
        fighter(opponent, 'npc-opponent'),
      ],
      events: const [],
      status: 'active',
      localDevelopmentOpponent: true,
    );
    _developmentBattles[matchId] = state;
    return state;
  }

  AuthoritativeBattleState _developmentAction(
    String matchId,
    int expectedRevision,
    TacticalAction action,
  ) {
    final current = _developmentBattles[matchId];
    if (current == null || current.revision != expectedRevision) {
      throw const NakamaException('Battle revision conflict');
    }
    var fighters = List<BattleCombatant>.of(current.fighters);
    var events = List<BattleEvent>.of(current.events);
    var revision = current.revision;
    String? winner;
    String status = current.status;

    void apply(int actorIndex, TacticalAction chosen) {
      final targetIndex = 1 - actorIndex;
      var actor = fighters[actorIndex];
      var target = fighters[targetIndex];
      if (chosen == TacticalAction.surrender) {
        winner = target.userId;
        status = 'surrendered';
      } else if (chosen == TacticalAction.guard) {
        actor = actor.copyWith(
          guarding: true,
          energy: (actor.energy + 25).clamp(0, 100),
        );
      } else {
        if (chosen == TacticalAction.ability &&
            actor.energy < DeterministicBattleRules.abilityCost) {
          throw const NakamaException('Not enough energy');
        }
        final damage = DeterministicBattleRules.damage(
          seed: matchId,
          sequence: revision + 1,
          actor: actor,
          target: target,
          action: chosen,
        );
        target = target.copyWith(
          hp: (target.hp - damage).clamp(0, 100),
          guarding: false,
        );
        actor = actor.copyWith(
          guarding: false,
          energy: chosen == TacticalAction.ability
              ? actor.energy - DeterministicBattleRules.abilityCost
              : (actor.energy + DeterministicBattleRules.energyPerTurn).clamp(
                  0,
                  100,
                ),
        );
        events.add(
          BattleEvent(
            sequence: revision + 1,
            actorCardId: actor.cardId,
            action: chosen,
            damage: damage,
            targetHp: target.hp,
          ),
        );
        if (!target.alive) {
          winner = actor.userId;
          status = 'complete';
        }
      }
      fighters[actorIndex] = actor;
      fighters[targetIndex] = target;
      revision++;
    }

    apply(0, action);
    if (status == 'active') {
      final bot = fighters[1];
      final botAction = bot.energy >= DeterministicBattleRules.abilityCost
          ? TacticalAction.ability
          : bot.hp < 35 && revision.isEven
          ? TacticalAction.guard
          : TacticalAction.attack;
      apply(1, botAction);
    }
    final state = AuthoritativeBattleState(
      matchId: current.matchId,
      revision: revision,
      turnUserId: 'local-player',
      turnDeadline: DateTime.now().toUtc().add(const Duration(seconds: 30)),
      fighters: fighters,
      events: events,
      status: status,
      winnerUserId: winner,
      localDevelopmentOpponent: true,
    );
    _developmentBattles[matchId] = state;
    return state;
  }

  Future<void> _saveMirror(String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cloud_bag_mirror', json);
  }

  CollectedCat _fromSync(Map<String, dynamic> m) {
    return CollectedCat(
      id: m['id'] as String,
      name: m['name'] as String? ?? 'Rival',
      breed: m['breed'] as String? ?? 'Mixed',
      breedConfidence: (m['breedConfidence'] as num?)?.toDouble() ?? 0.5,
      embedding: Float32List(128),
      createdAt:
          DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
      statsJson: jsonEncode(m['stats'] ?? {}),
      accentColor: m['accentColor'] as String? ?? '#EF4444',
      stars: (m['stars'] as int?) ?? 1,
      h3Cell: m['h3Cell'] as String? ?? 'unknown',
      lat: (m['lat'] as num?)?.toDouble(),
      lng: (m['lng'] as num?)?.toDouble(),
      wins: (m['wins'] as int?) ?? 0,
      losses: (m['losses'] as int?) ?? 0,
    );
  }
}
