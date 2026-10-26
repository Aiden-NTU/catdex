import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/cat.dart';
import '../models/scan_result.dart';

class CatRepository {
  CatRepository._(this._db);

  final Database _db;

  static const _tauHigh = 0.92;
  static const _tauLow = 0.78;
  static const cellCooldown = Duration(minutes: 15);

  static Future<CatRepository> open() async {
    final dir = await getApplicationDocumentsDirectory();
    return openAt(p.join(dir.path, 'catdex.db'));
  }

  static Future<CatRepository> openAt(String dbPath) async {
    final db = await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cats (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            breed TEXT NOT NULL,
            breed_confidence REAL NOT NULL,
            embedding BLOB NOT NULL,
            created_at TEXT NOT NULL,
            stats_json TEXT NOT NULL,
            image_path TEXT,
            accent_color TEXT,
            sticker TEXT,
            stars INTEGER DEFAULT 1,
            h3_cell TEXT,
            lat REAL,
            lng REAL,
            wins INTEGER DEFAULT 0,
            losses INTEGER DEFAULT 0,
            level INTEGER NOT NULL DEFAULT 1,
            xp INTEGER NOT NULL DEFAULT 0,
            energy INTEGER NOT NULL DEFAULT 100,
            hunger INTEGER NOT NULL DEFAULT 100,
            mood INTEGER NOT NULL DEFAULT 75,
            bond INTEGER NOT NULL DEFAULT 0,
            ability_mastery INTEGER NOT NULL DEFAULT 0,
            last_fed_at TEXT,
            last_played_at TEXT,
            last_groomed_at TEXT,
            last_trained_at TEXT,
            last_rested_at TEXT,
            progression_updated_at TEXT
          )
        ''');
        await _createAccountCache(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE cats ADD COLUMN stars INTEGER DEFAULT 1',
          );
          await db.execute('ALTER TABLE cats ADD COLUMN h3_cell TEXT');
          await db.execute('ALTER TABLE cats ADD COLUMN lat REAL');
          await db.execute('ALTER TABLE cats ADD COLUMN lng REAL');
          await db.execute(
            'ALTER TABLE cats ADD COLUMN wins INTEGER DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE cats ADD COLUMN losses INTEGER DEFAULT 0',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE cats ADD COLUMN level INTEGER NOT NULL DEFAULT 1',
          );
          await db.execute(
            'ALTER TABLE cats ADD COLUMN xp INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE cats ADD COLUMN energy INTEGER NOT NULL DEFAULT 100',
          );
          await db.execute(
            'ALTER TABLE cats ADD COLUMN hunger INTEGER NOT NULL DEFAULT 100',
          );
          await db.execute(
            'ALTER TABLE cats ADD COLUMN mood INTEGER NOT NULL DEFAULT 75',
          );
          await db.execute(
            'ALTER TABLE cats ADD COLUMN bond INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE cats ADD COLUMN ability_mastery INTEGER NOT NULL DEFAULT 0',
          );
          for (final column in [
            'last_fed_at',
            'last_played_at',
            'last_groomed_at',
            'last_trained_at',
            'last_rested_at',
            'progression_updated_at',
          ]) {
            await db.execute('ALTER TABLE cats ADD COLUMN $column TEXT');
          }
          await _createAccountCache(db);
        }
      },
    );
    return CatRepository._(db);
  }

  static Future<void> _createAccountCache(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS account_cache (
        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
        paw_coins INTEGER NOT NULL DEFAULT 0,
        daily_earned INTEGER NOT NULL DEFAULT 0,
        daily_cap INTEGER NOT NULL DEFAULT 100,
        treats INTEGER NOT NULL DEFAULT 0,
        grooming_supplies INTEGER NOT NULL DEFAULT 0,
        day_bucket TEXT,
        updated_at TEXT
      )
    ''');
  }

  Future<List<CollectedCat>> getAll() async {
    final rows = await _db.query('cats', orderBy: 'created_at DESC');
    return rows.map(CollectedCat.fromMap).toList();
  }

  Future<CollectedCat?> getById(String id) async {
    final rows = await _db.query('cats', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return CollectedCat.fromMap(rows.first);
  }

  Future<void> insert(CollectedCat cat) async {
    await _db.insert('cats', cat.toMap());
  }

  Future<void> update(CollectedCat cat) async {
    await _db.update('cats', cat.toMap(), where: 'id = ?', whereArgs: [cat.id]);
  }

  Future<void> applyServerCard(Map<String, dynamic> value) async {
    final id = value['id'] as String?;
    if (id == null || id.isEmpty) return;
    final cat = await getById(id);
    if (cat == null) return;
    cat.applyServerJson(value);
    await update(cat);
  }

  Future<CareAccountCache> getAccountCache() async {
    final rows = await _db.query(
      'account_cache',
      where: 'singleton = 1',
      limit: 1,
    );
    if (rows.isEmpty) return const CareAccountCache();
    return CareAccountCache.fromMap(rows.first);
  }

  Future<void> updateAccountCache(Map<String, dynamic> value) async {
    await _db.insert('account_cache', {
      'singleton': 1,
      'paw_coins': (value['pawCoins'] as num?)?.toInt() ?? 0,
      'daily_earned': (value['dailyEarned'] as num?)?.toInt() ?? 0,
      'daily_cap': (value['dailyCap'] as num?)?.toInt() ?? 100,
      'treats': (value['treats'] as num?)?.toInt() ?? 0,
      'grooming_supplies': (value['groomingSupplies'] as num?)?.toInt() ?? 0,
      'day_bucket': value['dayBucket'] as String?,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    final cat = await getById(id);
    if (cat?.imagePath != null) {
      final f = File(cat!.imagePath!);
      if (await f.exists()) await f.delete();
    }
    await _db.delete('cats', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> isCellOnCooldown(String cellId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'cell_cd_$cellId';
    final raw = prefs.getString(key);
    if (raw == null) return false;
    final until = DateTime.tryParse(raw);
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  Future<void> markCellCooldown(String cellId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'cell_cd_$cellId',
      DateTime.now().add(cellCooldown).toIso8601String(),
    );
  }

  static double cosineSimilarity(Float32List a, Float32List b) {
    final n = a.length < b.length ? a.length : b.length;
    var dot = 0.0;
    var na = 0.0;
    var nb = 0.0;
    for (var i = 0; i < n; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  Future<IdentityMatch> matchIdentity(Float32List embedding) async {
    final cats = await getAll();
    if (cats.isEmpty) {
      return const IdentityMatch(
        decision: MatchDecision.unique,
        bestSimilarity: 0,
      );
    }

    CollectedCat? best;
    var bestSim = -1.0;
    for (final cat in cats) {
      final sim = cosineSimilarity(embedding, cat.embedding);
      if (sim > bestSim) {
        bestSim = sim;
        best = cat;
      }
    }

    if (bestSim >= _tauHigh) {
      return IdentityMatch(
        decision: MatchDecision.duplicate,
        bestSimilarity: bestSim,
        matchedCat: best,
      );
    }
    if (bestSim <= _tauLow) {
      return IdentityMatch(
        decision: MatchDecision.unique,
        bestSimilarity: bestSim,
        matchedCat: best,
      );
    }
    return IdentityMatch(
      decision: MatchDecision.ambiguous,
      bestSimilarity: bestSim,
      matchedCat: best,
    );
  }

  Future<String> saveCropImage(String catId, List<int> jpegBytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(dir.path, 'cat_images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    final path = p.join(imagesDir.path, '$catId.jpg');
    await File(path).writeAsBytes(jpegBytes);
    return path;
  }

  Future<void> close() => _db.close();
}

class CareAccountCache {
  const CareAccountCache({
    this.pawCoins = 0,
    this.dailyEarned = 0,
    this.dailyCap = 100,
    this.treats = 0,
    this.groomingSupplies = 0,
  });

  final int pawCoins;
  final int dailyEarned;
  final int dailyCap;
  final int treats;
  final int groomingSupplies;

  factory CareAccountCache.fromMap(Map<String, Object?> map) =>
      CareAccountCache(
        pawCoins: (map['paw_coins'] as num?)?.toInt() ?? 0,
        dailyEarned: (map['daily_earned'] as num?)?.toInt() ?? 0,
        dailyCap: (map['daily_cap'] as num?)?.toInt() ?? 100,
        treats: (map['treats'] as num?)?.toInt() ?? 0,
        groomingSupplies: (map['grooming_supplies'] as num?)?.toInt() ?? 0,
      );
}
