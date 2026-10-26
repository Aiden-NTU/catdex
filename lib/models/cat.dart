import 'dart:convert';
import 'dart:typed_data';

class CollectedCat {
  CollectedCat({
    required this.id,
    required this.name,
    required this.breed,
    required this.breedConfidence,
    required this.embedding,
    required this.createdAt,
    required this.statsJson,
    this.imagePath,
    this.accentColor = '#6B7280',
    this.sticker = 'none',
    this.stars = 1,
    this.h3Cell = 'unknown',
    this.lat,
    this.lng,
    this.wins = 0,
    this.losses = 0,
    this.level = 1,
    this.xp = 0,
    this.energy = 100,
    this.hunger = 100,
    this.mood = 75,
    this.bond = 0,
    this.abilityMastery = 0,
    this.lastFedAt,
    this.lastPlayedAt,
    this.lastGroomedAt,
    this.lastTrainedAt,
    this.lastRestedAt,
    this.progressionUpdatedAt,
  });

  final String id;
  String name;
  final String breed;
  final double breedConfidence;
  final Float32List embedding;
  final DateTime createdAt;
  String statsJson;
  final String? imagePath;
  String accentColor;
  String sticker;
  final int stars;
  final String h3Cell;
  final double? lat;
  final double? lng;
  int wins;
  int losses;
  int level;
  int xp;
  int energy;
  int hunger;
  int mood;
  int bond;
  int abilityMastery;
  DateTime? lastFedAt;
  DateTime? lastPlayedAt;
  DateTime? lastGroomedAt;
  DateTime? lastTrainedAt;
  DateTime? lastRestedAt;
  DateTime? progressionUpdatedAt;

  int get xpForNextLevel => level >= 40 ? 0 : 100 * level * level;

  double get levelProgress {
    if (level >= 40) return 1;
    final floor = totalXpForLevel(level);
    return ((xp - floor) / xpForNextLevel).clamp(0.0, 1.0);
  }

  static int totalXpForLevel(int value) {
    final n = value - 1;
    return 100 * n * (n + 1) * (2 * n + 1) ~/ 6;
  }

  Map<String, dynamic> get stats =>
      _serverStats ?? jsonDecode(statsJson) as Map<String, dynamic>;

  int get battlePower => (stats['battlePower'] as num?)?.toInt() ?? 0;
  int get attack => (stats['attack'] as num?)?.toInt() ?? 50;
  int get defense => (stats['defense'] as num?)?.toInt() ?? 50;
  int get speed => (stats['speed'] as num?)?.toInt() ?? 50;
  String get ability => (stats['ability'] as String?) ?? 'Wildcard';

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'breed': breed,
    'breed_confidence': breedConfidence,
    'embedding': Uint8List.fromList(
      embedding.buffer.asUint8List(
        embedding.offsetInBytes,
        embedding.lengthInBytes,
      ),
    ),
    'created_at': createdAt.toIso8601String(),
    'stats_json': statsJson,
    'image_path': imagePath,
    'accent_color': accentColor,
    'sticker': sticker,
    'stars': stars,
    'h3_cell': h3Cell,
    'lat': lat,
    'lng': lng,
    'wins': wins,
    'losses': losses,
    'level': level,
    'xp': xp,
    'energy': energy,
    'hunger': hunger,
    'mood': mood,
    'bond': bond,
    'ability_mastery': abilityMastery,
    'last_fed_at': lastFedAt?.toUtc().toIso8601String(),
    'last_played_at': lastPlayedAt?.toUtc().toIso8601String(),
    'last_groomed_at': lastGroomedAt?.toUtc().toIso8601String(),
    'last_trained_at': lastTrainedAt?.toUtc().toIso8601String(),
    'last_rested_at': lastRestedAt?.toUtc().toIso8601String(),
    'progression_updated_at': progressionUpdatedAt?.toUtc().toIso8601String(),
  };

  Map<String, dynamic> toSyncJson() => {
    'id': id,
    'name': name,
    'breed': breed,
    'breedConfidence': breedConfidence,
    'createdAt': createdAt.toIso8601String(),
    'stats': stats,
    'accentColor': accentColor,
    'sticker': sticker,
    'stars': stars,
    'h3Cell': h3Cell,
    'lat': lat,
    'lng': lng,
    'wins': wins,
    'losses': losses,
    // These are cache hints only. The server never trusts progression.
    'level': level,
    'xp': xp,
  };

  factory CollectedCat.fromMap(Map<String, dynamic> map) {
    final embBytes = map['embedding'] as Uint8List;
    final floats = Float32List(embBytes.lengthInBytes ~/ 4);
    floats.buffer.asUint8List().setAll(0, embBytes);
    return CollectedCat(
      id: map['id'] as String,
      name: map['name'] as String,
      breed: map['breed'] as String,
      breedConfidence: (map['breed_confidence'] as num).toDouble(),
      embedding: floats,
      createdAt: DateTime.parse(map['created_at'] as String),
      statsJson: map['stats_json'] as String,
      imagePath: map['image_path'] as String?,
      accentColor: (map['accent_color'] as String?) ?? '#6B7280',
      sticker: (map['sticker'] as String?) ?? 'none',
      stars: (map['stars'] as int?) ?? 1,
      h3Cell: (map['h3_cell'] as String?) ?? 'unknown',
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      wins: (map['wins'] as int?) ?? 0,
      losses: (map['losses'] as int?) ?? 0,
      level: (map['level'] as num?)?.toInt() ?? 1,
      xp: (map['xp'] as num?)?.toInt() ?? 0,
      energy: (map['energy'] as num?)?.toInt() ?? 100,
      hunger: (map['hunger'] as num?)?.toInt() ?? 100,
      mood: (map['mood'] as num?)?.toInt() ?? 75,
      bond: (map['bond'] as num?)?.toInt() ?? 0,
      abilityMastery: (map['ability_mastery'] as num?)?.toInt() ?? 0,
      lastFedAt: _date(map['last_fed_at']),
      lastPlayedAt: _date(map['last_played_at']),
      lastGroomedAt: _date(map['last_groomed_at']),
      lastTrainedAt: _date(map['last_trained_at']),
      lastRestedAt: _date(map['last_rested_at']),
      progressionUpdatedAt: _date(map['progression_updated_at']),
    );
  }

  void applyServerJson(Map<String, dynamic> value) {
    level = (value['level'] as num?)?.toInt() ?? level;
    xp = (value['xp'] as num?)?.toInt() ?? xp;
    energy = (value['energy'] as num?)?.toInt() ?? energy;
    hunger = (value['hunger'] as num?)?.toInt() ?? hunger;
    mood = (value['mood'] as num?)?.toInt() ?? mood;
    bond = (value['bond'] as num?)?.toInt() ?? bond;
    abilityMastery =
        (value['abilityMastery'] as num?)?.toInt() ?? abilityMastery;
    lastFedAt = _date(value['lastFedAt']) ?? lastFedAt;
    lastPlayedAt = _date(value['lastPlayedAt']) ?? lastPlayedAt;
    lastGroomedAt = _date(value['lastGroomedAt']) ?? lastGroomedAt;
    lastTrainedAt = _date(value['lastTrainedAt']) ?? lastTrainedAt;
    lastRestedAt = _date(value['lastRestedAt']) ?? lastRestedAt;
    progressionUpdatedAt =
        _date(value['progressionUpdatedAt']) ?? DateTime.now().toUtc();
    final serverStats = value['stats'];
    if (serverStats is Map) {
      final merged = <String, dynamic>{
        ...stats,
        ...serverStats.cast<String, dynamic>(),
      };
      _serverStats = merged;
      statsJson = jsonEncode(merged);
    }
  }

  Map<String, dynamic>? _serverStats;

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}
