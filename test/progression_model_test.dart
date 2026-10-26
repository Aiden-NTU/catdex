import 'dart:io';
import 'dart:typed_data';

import 'package:catdex/data/cat_repository.dart';
import 'package:catdex/models/cat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('cat progression parses defaults and authoritative server state', () {
    final cat = CollectedCat(
      id: 'cat',
      name: 'Miso',
      breed: 'Mixed',
      breedConfidence: .8,
      embedding: Float32List.fromList([.1, .2]),
      createdAt: DateTime.utc(2026),
      statsJson: '{"attack":50,"defense":50,"speed":50,"battlePower":150}',
    );

    expect(cat.level, 1);
    expect(cat.energy, 100);
    expect(CollectedCat.totalXpForLevel(3), 500);

    cat.applyServerJson({
      'level': 3,
      'xp': 550,
      'energy': 72,
      'hunger': 64,
      'mood': 90,
      'bond': 33,
      'abilityMastery': 20,
      'stats': {'attack': 57, 'defense': 56, 'speed': 55, 'battlePower': 168},
    });

    expect(cat.level, 3);
    expect(cat.levelProgress, closeTo(50 / 900, .0001));
    expect(cat.battlePower, 168);
  });

  test(
    'v2 database migrates additively without changing local media',
    () async {
      final temp = await Directory.systemTemp.createTemp('catdex-migration-');
      addTearDown(() => temp.delete(recursive: true));
      final path = '${temp.path}/catdex.db';
      final old = await openDatabase(
        path,
        version: 2,
        onCreate: (db, _) async {
          await db.execute('''
          CREATE TABLE cats (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, breed TEXT NOT NULL,
            breed_confidence REAL NOT NULL, embedding BLOB NOT NULL,
            created_at TEXT NOT NULL, stats_json TEXT NOT NULL,
            image_path TEXT, accent_color TEXT, sticker TEXT,
            stars INTEGER DEFAULT 1, h3_cell TEXT, lat REAL, lng REAL,
            wins INTEGER DEFAULT 0, losses INTEGER DEFAULT 0
          )
        ''');
        },
      );
      final embedding = Float32List.fromList([.2, .4, .8]);
      await old.insert('cats', {
        'id': 'legacy',
        'name': 'Legacy',
        'breed': 'Mixed',
        'breed_confidence': .7,
        'embedding': embedding.buffer.asUint8List(),
        'created_at': DateTime.utc(2025).toIso8601String(),
        'stats_json': '{"attack":40,"defense":50,"speed":60,"battlePower":150}',
        'image_path': '/kept/cat.jpg',
      });
      await old.close();

      final repository = await CatRepository.openAt(path);
      addTearDown(repository.close);
      final cat = await repository.getById('legacy');

      expect(cat, isNotNull);
      expect(cat!.imagePath, '/kept/cat.jpg');
      expect(cat.embedding, orderedEquals(embedding));
      expect(cat.level, 1);
      expect(cat.energy, 100);
      expect(cat.hunger, 100);
      expect(cat.mood, 75);
      expect(cat.bond, 0);
      expect((await repository.getAccountCache()).dailyCap, 100);
    },
  );
}
