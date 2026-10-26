import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/breed_info.dart';

class StarRoll {
  const StarRoll({
    required this.stars,
    required this.multiplier,
    required this.baseAttack,
    required this.baseDefense,
    required this.baseSpeed,
    required this.finalAttack,
    required this.finalDefense,
    required this.finalSpeed,
    required this.battlePower,
  });

  final int stars;
  final double multiplier;
  final int baseAttack;
  final int baseDefense;
  final int baseSpeed;
  final int finalAttack;
  final int finalDefense;
  final int finalSpeed;
  final int battlePower;

  Map<String, dynamic> toStatsJson(BreedInfo info) => {
        'attack': finalAttack,
        'defense': finalDefense,
        'speed': finalSpeed,
        'baseAttack': baseAttack,
        'baseDefense': baseDefense,
        'baseSpeed': baseSpeed,
        'ability': info.ability,
        'abilityDesc': info.abilityDesc,
        'battlePower': battlePower,
        'stars': stars,
        'multiplier': multiplier,
      };
}

/// Deterministic star roll from embedding + cell + day.
class StarRank {
  /// Weighted: 1★40% 2★30% 3★18% 4★9% 5★3%
  static int rollStars({
    required Float32List embedding,
    required String h3Cell,
    DateTime? at,
  }) {
    final day = (at ?? DateTime.now()).toUtc();
    final dayBucket = '${day.year}-${day.month}-${day.day}';
    final embBytes = embedding.buffer.asUint8List(
      embedding.offsetInBytes,
      embedding.lengthInBytes,
    );
    final digest = sha256.convert([
      ...utf8.encode('$h3Cell|$dayBucket|'),
      ...embBytes,
    ]);
    final seed = digest.bytes.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
    final rng = Random(seed);
    final r = rng.nextDouble();
    if (r < 0.40) return 1;
    if (r < 0.70) return 2;
    if (r < 0.88) return 3;
    if (r < 0.97) return 4;
    return 5;
  }

  static double multiplierFor(int stars) => 1.0 + 0.12 * (stars - 1);

  static StarRoll apply(BreedInfo info, int stars) {
    final m = multiplierFor(stars);
    int scale(int v) => (v * m).round().clamp(1, 150);
    final atk = scale(info.attack);
    final def = scale(info.defense);
    final spd = scale(info.speed);
    return StarRoll(
      stars: stars,
      multiplier: m,
      baseAttack: info.attack,
      baseDefense: info.defense,
      baseSpeed: info.speed,
      finalAttack: atk,
      finalDefense: def,
      finalSpeed: spd,
      battlePower: atk + def + spd,
    );
  }

  static StarRoll fromBreed({
    required BreedInfo info,
    required Float32List embedding,
    required String h3Cell,
    DateTime? at,
  }) {
    final stars = rollStars(embedding: embedding, h3Cell: h3Cell, at: at);
    return apply(info, stars);
  }
}
