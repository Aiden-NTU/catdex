import 'package:flutter/material.dart';

import '../data/cat_repository.dart';
import '../data/demo_pack.dart';
import '../game/battle_engine.dart';
import '../models/cat.dart';
import '../services/sync_service.dart';
import 'battle/immersive_battle_screen.dart';

class BattleLobbyScreen extends StatefulWidget {
  const BattleLobbyScreen({
    super.key,
    required this.repository,
    required this.sync,
  });

  final CatRepository repository;
  final SyncService sync;

  @override
  State<BattleLobbyScreen> createState() => _BattleLobbyScreenState();
}

class _BattleLobbyScreenState extends State<BattleLobbyScreen> {
  List<CollectedCat> _cats = [];
  CollectedCat? _selected;
  bool _loading = true;

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

  Future<void> _start() async {
    final mine = _selected;
    if (mine == null) return;
    CollectedCat? rival;
    try {
      rival = await widget.sync.ghostOpponent(mine);
    } catch (_) {
      rival = null;
    }
    rival ??= CollectedCat(
      id: 'ghost-${mine.id}',
      name: 'Street rival',
      breed: mine.breed,
      breedConfidence: mine.breedConfidence,
      embedding: mine.embedding,
      createdAt: DateTime.now(),
      statsJson: mine.statsJson,
      accentColor: '#EF4444',
      stars: mine.stars,
      h3Cell: mine.h3Cell,
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImmersiveBattleScreen(
          repository: widget.repository,
          sync: widget.sync,
          mine: mine,
          rival: rival!,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_cats.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'You need a cat before you can fight.',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                await DemoPack.seedIfEmpty(widget.repository);
                await _load();
                await _start();
              },
              child: const Text('Get a practice cat and fight'),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Pick a cat',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Then hit Fight. A rival shows up on the street.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: _cats.length,
              itemBuilder: (context, i) {
                final c = _cats[i];
                final selected = _selected?.id == c.id;
                return ListTile(
                  selected: selected,
                  selectedTileColor: const Color(0xFF292524),
                  leading: Text(
                    '★' * c.stars,
                    style: const TextStyle(color: Color(0xFFFBBF24)),
                  ),
                  title: Text(c.name, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    '${c.breed} · PWR ${c.battlePower} · ${c.wins}W/${c.losses}L',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  onTap: () => setState(() => _selected = c),
                );
              },
            ),
          ),
          FilledButton(
            onPressed: _start,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Fight'),
          ),
        ],
      ),
    );
  }
}

class BattleArenaScreen extends StatefulWidget {
  const BattleArenaScreen({
    super.key,
    required this.repository,
    required this.mine,
    required this.rival,
  });

  final CatRepository repository;
  final CollectedCat mine;
  final CollectedCat rival;

  @override
  State<BattleArenaScreen> createState() => _BattleArenaScreenState();
}

class _BattleArenaScreenState extends State<BattleArenaScreen> {
  late final BattleEngine _engine;
  late final BattleFighter _a;
  late final BattleFighter _b;
  BattleResult? _result;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _a = BattleFighter(widget.mine);
    _b = BattleFighter(widget.rival);
    _engine = BattleEngine(_a, _b);
  }

  Future<void> _autoFight() async {
    setState(() => _running = true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final result = _engine.runAuto();
    final winnerMine = result.winnerId == widget.mine.id;
    final updated = widget.mine;
    if (winnerMine) {
      updated.wins += 1;
    } else {
      updated.losses += 1;
    }
    await widget.repository.update(updated);
    if (!mounted) return;
    setState(() {
      _result = result;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A09),
      appBar: AppBar(
        title: const Text('Battle'),
        backgroundColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _HpBar(fighter: _a, color: const Color(0xFFFDBA74)),
            const SizedBox(height: 8),
            const Text('VS', style: TextStyle(color: Colors.white38)),
            const SizedBox(height: 8),
            _HpBar(fighter: _b, color: const Color(0xFFEF4444)),
            const SizedBox(height: 16),
            if (_result == null && !_running)
              FilledButton(
                onPressed: _autoFight,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Start auto-battle'),
              ),
            if (_running) const CircularProgressIndicator(),
            if (_result != null) ...[
              Text(
                _result!.winnerId == widget.mine.id
                    ? 'Victory!'
                    : 'Defeat…',
                style: TextStyle(
                  color: _result!.winnerId == widget.mine.id
                      ? const Color(0xFF86EFAC)
                      : const Color(0xFFF87171),
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: ListView.builder(
                itemCount: _engine.log.length,
                itemBuilder: (context, i) {
                  final line = _engine.log[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      line.text,
                      style: TextStyle(
                        color: line.highlight
                            ? const Color(0xFFFDE68A)
                            : Colors.white70,
                        fontWeight:
                            line.highlight ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HpBar extends StatelessWidget {
  const _HpBar({required this.fighter, required this.color});
  final BattleFighter fighter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${fighter.name}  ${'★' * fighter.stars}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text('HP ${fighter.hp}', style: TextStyle(color: color)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fighter.hp / 100,
            minHeight: 10,
            color: color,
            backgroundColor: Colors.white12,
          ),
        ),
      ],
    );
  }
}
