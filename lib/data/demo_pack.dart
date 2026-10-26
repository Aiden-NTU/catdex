import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../game/star_rank.dart';
import '../models/cat.dart';
import 'breed_catalog.dart';
import 'cat_repository.dart';

/// Lecture / desktop entertainment: seed synthetic cards when the bag is empty.
class DemoPack {
  static Future<int> seedIfEmpty(CatRepository repository) async {
    final existing = await repository.getAll();
    if (existing.isNotEmpty) return 0;

    final catalog = await BreedCatalog.load();
    final rng = Random(42);
    const breeds = ['Bengal', 'Siamese', 'Maine Coon', 'Bombay'];
    var added = 0;

    for (final key in breeds) {
      final info = catalog.resolve(key);
      final emb = Float32List(128);
      for (var i = 0; i < 128; i++) {
        emb[i] = rng.nextDouble() * 2 - 1;
      }
      var norm = 0.0;
      for (final v in emb) {
        norm += v * v;
      }
      norm = sqrt(norm);
      if (norm > 0) {
        for (var i = 0; i < emb.length; i++) {
          emb[i] /= norm;
        }
      }

      final cell = 'demo_${added}_0';
      final roll = StarRank.fromBreed(
        info: info,
        embedding: emb,
        h3Cell: cell,
      );
      await repository.insert(
        CollectedCat(
          id: const Uuid().v4(),
          name: info.displayName,
          breed: info.displayName,
          breedConfidence: 0.91,
          embedding: emb,
          createdAt: DateTime.now(),
          statsJson: jsonEncode(roll.toStatsJson(info)),
          accentColor: info.accent,
          stars: roll.stars,
          h3Cell: cell,
          lat: 51.5 + added * 0.001,
          lng: -0.12,
        ),
      );
      added++;
    }
    return added;
  }
}
