import 'dart:io';

import 'package:flutter/material.dart';

import '../data/cat_repository.dart';
import '../models/cat.dart';
import '../widgets/cat_card_frame.dart';
import 'care/care_room_screen.dart';

class CatDetailScreen extends StatefulWidget {
  const CatDetailScreen({
    super.key,
    required this.repository,
    required this.catId,
  });

  final CatRepository repository;
  final String catId;

  @override
  State<CatDetailScreen> createState() => _CatDetailScreenState();
}

class _CatDetailScreenState extends State<CatDetailScreen> {
  CollectedCat? _cat;
  bool _loading = true;
  final _nameController = TextEditingController();

  static const _stickers = ['none', 'crown', 'bandana', 'sunglasses', 'bow'];
  static const _accents = [
    '#C47A3A',
    '#B45309',
    '#E8D5B7',
    '#6B7280',
    '#8B5CF6',
    '#0EA5E9',
    '#EF4444',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cat = await widget.repository.getById(widget.catId);
    if (!mounted) return;
    setState(() {
      _cat = cat;
      _loading = false;
      _nameController.text = cat?.name ?? '';
    });
  }

  Future<void> _save() async {
    final cat = _cat;
    if (cat == null) return;
    cat.name = _nameController.text.trim().isEmpty
        ? cat.name
        : _nameController.text.trim();
    await widget.repository.update(cat);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved')));
    setState(() {});
  }

  Color _parse(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cat = _cat;
    if (cat == null) {
      return Scaffold(
        body: Center(
          child: _loading
              ? Semantics(
                  label: 'Loading cat details',
                  liveRegion: true,
                  child: CircularProgressIndicator(),
                )
              : const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'This cat could not be found.',
                    textAlign: TextAlign.center,
                  ),
                ),
        ),
      );
    }

    final accent = _parse(cat.accentColor);
    final stats = cat.stats;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0A09),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(cat.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Release ${cat.name}',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Release this cat?'),
                  content: Text('Remove ${cat.name} from your Catdex.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Release'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await widget.repository.delete(cat.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AspectRatio(
                aspectRatio: .75,
                child: Semantics(
                  label:
                      '${cat.name} card, ${cat.breed}, ${cat.stars} of 5 stars',
                  image: true,
                  child: CatCardFrame(
                    sticker: cat.sticker,
                    image:
                        cat.imagePath != null &&
                            File(cat.imagePath!).existsSync()
                        ? Image.file(
                            File(cat.imagePath!),
                            fit: BoxFit.cover,
                            semanticLabel: 'Photo of ${cat.name}',
                          )
                        : ColoredBox(
                            color: accent.withValues(alpha: 0.3),
                            child: const Center(
                              child: Icon(
                                Icons.pets_rounded,
                                size: 80,
                                color: Color(0xFF312E81),
                              ),
                            ),
                          ),
                    footer: ExcludeSemantics(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              cat.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${cat.breed} · PWR ${cat.battlePower}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CareRoomScreen(
                    repository: widget.repository,
                    catId: cat.id,
                  ),
                ),
              );
              await _load();
            },
            icon: const Icon(Icons.favorite),
            label: Text('Visit care room · Lv ${cat.level}'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF9A8D4),
              foregroundColor: const Color(0xFF3B1029),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Name',
              labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: accent.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: accent),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            cat.breed,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${'★' * cat.stars}${'☆' * (5 - cat.stars)}',
            style: const TextStyle(
              color: Color(0xFFFBBF24),
              fontSize: 20,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Confidence ${(cat.breedConfidence * 100).toStringAsFixed(0)}%'
            ' · W ${cat.wins} / L ${cat.losses}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
          if (cat.h3Cell != 'unknown') ...[
            const SizedBox(height: 4),
            Text(
              'Caught in ${cat.h3Cell}'
              '${cat.lat != null ? ' (${cat.lat!.toStringAsFixed(4)}, ${cat.lng!.toStringAsFixed(4)})' : ''}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 20),
          _StatRow(label: 'Attack', value: stats['attack'] ?? 0, color: accent),
          _StatRow(
            label: 'Defense',
            value: stats['defense'] ?? 0,
            color: accent,
          ),
          _StatRow(label: 'Speed', value: stats['speed'] ?? 0, color: accent),
          const SizedBox(height: 8),
          Text(
            'Battle power ${stats['battlePower'] ?? 0}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${stats['ability'] ?? '—'}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
          ),
          const SizedBox(height: 24),
          const Text(
            'Accent',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _accents.map((hex) {
              final c = _parse(hex);
              final selected =
                  cat.accentColor.toUpperCase() == hex.toUpperCase();
              return Semantics(
                button: true,
                selected: selected,
                label: 'Accent color $hex',
                child: Tooltip(
                  message: 'Accent $hex',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => cat.accentColor = hex),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? Colors.white : Colors.white24,
                          width: selected ? 3 : 1,
                        ),
                      ),
                      child: selected
                          ? const Icon(Icons.check_rounded, color: Colors.white)
                          : null,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          const Text(
            'Sticker',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _stickers.map((s) {
              final selected = cat.sticker == s;
              return ChoiceChip(
                avatar: s == 'none'
                    ? const Icon(Icons.block_rounded, size: 18)
                    : CatSticker(name: s, size: 24, semanticLabel: ''),
                label: Text(s == 'none' ? 'No sticker' : s),
                selected: selected,
                onSelected: (_) => setState(() => cat.sticker = s),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Save changes'),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Expanded(
            child: Semantics(
              label: '$label $value out of 100',
              value: '$value percent',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (value / 100).clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: Colors.white12,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$value', style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}
