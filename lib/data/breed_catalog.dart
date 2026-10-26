import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/breed_info.dart';

class BreedCatalog {
  BreedCatalog._(this._byKey);

  final Map<String, BreedInfo> _byKey;

  static BreedCatalog? _instance;

  static Future<BreedCatalog> load() async {
    if (_instance != null) return _instance!;
    final raw = await rootBundle.loadString('assets/data/breeds.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final byKey = <String, BreedInfo>{};
    for (final entry in map.entries) {
      byKey[entry.key] = BreedInfo.fromJson(
        entry.key,
        entry.value as Map<String, dynamic>,
      );
    }
    _instance = BreedCatalog._(byKey);
    return _instance!;
  }

  BreedInfo get mixed => _byKey['Mixed']!;

  BreedInfo resolve(String key) {
    if (_byKey.containsKey(key)) return _byKey[key]!;
    final lower = key.toLowerCase().replaceAll('_', ' ').trim();
    for (final e in _byKey.entries) {
      if (e.key.toLowerCase() == lower) return e.value;
      if (e.value.displayName.toLowerCase() == lower) return e.value;
      if (e.key.toLowerCase().replaceAll('_', ' ') == lower) return e.value;
    }
    // Fuzzy contains match on display name tokens
    for (final e in _byKey.entries) {
      final name = e.value.displayName.toLowerCase();
      if (lower.contains(name) || name.contains(lower)) return e.value;
    }
    return mixed;
  }

  List<BreedInfo> get all => _byKey.values.toList();
}
