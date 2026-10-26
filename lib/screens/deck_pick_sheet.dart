import 'package:flutter/material.dart';

import '../data/cat_repository.dart';
import '../data/demo_pack.dart';
import '../models/cat.dart';
import 'dart:math' as math;

import '../data/breed_catalog.dart';
import '../services/sync_service.dart';
import 'battle/immersive_battle_screen.dart';
import 'battle/spam_duel_screen.dart';
import '../game/battle/spam_battle_engine.dart';

/// Pick a cat, then duel.
///
/// [npcEncounterId] non-null → scripted area/cohort encounter (local rules).
/// Otherwise tries real Nakama matchmaking and refuses to invent a player.
Future<void> showDeckPickAndDuel(
  BuildContext context, {
  required CatRepository repository,
  required SyncService sync,
  required String rivalName,
  String? npcEncounterId,
}) async {
  final chosen = await showModalBottomSheet<CollectedCat>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DeckPickSheet(repository: repository),
  );
  if (chosen == null || !context.mounted) return;

  CollectedCat? rival;
  if (npcEncounterId != null) {
    final catalog = await BreedCatalog.load();
    final breeds = catalog.all.map((b) => b.key).toList();
    final pick = breeds.isEmpty
        ? chosen.breed
        : breeds[math.Random(npcEncounterId.hashCode).nextInt(breeds.length)];
    final info = catalog.resolve(pick);
    rival = CollectedCat(
      id: npcEncounterId.startsWith('enc-')
          ? npcEncounterId
          : 'enc-$npcEncounterId',
      name: rivalName,
      breed: info.displayName,
      breedConfidence: 0.9,
      embedding: chosen.embedding,
      createdAt: DateTime.now(),
      statsJson:
          '{"attack":${info.attack},"defense":${info.defense},"speed":${info.speed},"ability":"${info.ability}","battlePower":${info.battlePower}}',
      accentColor: info.accent,
      stars: chosen.stars.clamp(1, 5),
      h3Cell: chosen.h3Cell,
      imagePath: null, // spam duel falls back to demo art
    );
  } else {
    try {
      rival = await sync.ghostOpponent(chosen);
    } catch (_) {
      rival = null;
    }
    if (rival == null) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No players nearby'),
          content: const Text(
            'Matchmaking found nobody in this cell. '
            'Challenge a red area encounter on the map, or wait for another player.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
  }

  if (!context.mounted) return;
  if (npcEncounterId != null) {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SpamDuelScreen(
          mine: chosen,
          rival: rival!,
          difficulty: NpcDifficulty.normal,
        ),
      ),
    );
  } else {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImmersiveBattleScreen(
          repository: repository,
          sync: sync,
          mine: chosen,
          rival: rival!,
        ),
      ),
    );
  }
}

class DeckPickSheet extends StatefulWidget {
  const DeckPickSheet({super.key, required this.repository});

  final CatRepository repository;

  @override
  State<DeckPickSheet> createState() => _DeckPickSheetState();
}

class _DeckPickSheetState extends State<DeckPickSheet> {
  List<CollectedCat> _cats = [];
  bool _loading = true;
  CollectedCat? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cats = await widget.repository.getAll();
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _selected = cats.isEmpty ? null : cats.first;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.62;
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Color(0xFF1C1917),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Choose your fighter',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'One card enters the duel field.',
            style: TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 12),
          Expanded(child: _body()),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _selected == null
                ? null
                : () => Navigator.pop(context, _selected),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFDBA74),
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(52),
            ),
            child: const Text(
              'Enter duel',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_cats.isEmpty) {
      return Center(
        child: FilledButton.tonal(
          onPressed: () async {
            await DemoPack.seedIfEmpty(widget.repository);
            await _load();
          },
          child: const Text('Get a practice cat first'),
        ),
      );
    }
    return ListView.separated(
      itemCount: _cats.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final cat = _cats[i];
        final selected = _selected?.id == cat.id;
        return Material(
          color: selected ? const Color(0xFF44403C) : const Color(0xFF292524),
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: selected ? const Color(0xFFFDBA74) : Colors.transparent,
                width: 2,
              ),
            ),
            leading: Text(
              '★' * cat.stars,
              style: const TextStyle(color: Color(0xFFFBBF24)),
            ),
            title: Text(
              cat.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              '${cat.breed} · PWR ${cat.battlePower}',
              style: const TextStyle(color: Colors.white54),
            ),
            onTap: () => setState(() => _selected = cat),
          ),
        );
      },
    );
  }
}
