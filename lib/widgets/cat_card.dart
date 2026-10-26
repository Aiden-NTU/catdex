import 'dart:io';

import 'package:flutter/material.dart';

import '../models/cat.dart';
import 'cat_card_frame.dart';

class CatCard extends StatefulWidget {
  const CatCard({super.key, required this.cat, required this.onTap});

  final CollectedCat cat;
  final VoidCallback onTap;

  @override
  State<CatCard> createState() => _CatCardState();
}

class _CatCardState extends State<CatCard> {
  bool _showStats = false;
  bool _focused = false;

  Color _parseAccent(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.tryParse('FF$h', radix: 16) ?? 0xFF6B7280);
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.cat;
    final accent = _parseAccent(cat.accentColor);
    final power = (cat.stats['battlePower'] as num?)?.toInt() ?? 0;
    final stars = '${'★' * cat.stars}${'☆' * (5 - cat.stars)}';

    return Semantics(
      button: true,
      label:
          '${cat.name}, ${cat.breed}, ${cat.stars} of 5 stars, battle power $power',
      hint: 'Open cat details. Long press to flip the card.',
      onLongPress: _toggleSide,
      child: FocusableActionDetector(
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        child: AnimatedScale(
          scale: _focused ? 1.025 : 1,
          duration: animationsEnabled(context)
              ? const Duration(milliseconds: 160)
              : Duration.zero,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              onLongPress: _toggleSide,
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _focused ? Colors.white : Colors.transparent,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: _focused ? .5 : .22),
                      blurRadius: _focused ? 18 : 8,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AnimatedSwitcher(
                    duration: animationsEnabled(context)
                        ? const Duration(milliseconds: 420)
                        : Duration.zero,
                    transitionBuilder: (child, animation) {
                      final turn = Tween(begin: .5, end: 0.0).animate(animation);
                      return AnimatedBuilder(
                        animation: turn,
                        child: child,
                        builder: (context, child) => Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationY(turn.value * 3.14159),
                          child: child,
                        ),
                      );
                    },
                    child: _showStats
                        ? _CardBack(
                            key: const ValueKey('back'),
                            cat: cat,
                            accent: accent,
                          )
                        : CatCardFrame(
                            key: const ValueKey('front'),
                            sticker: cat.sticker,
                            image: _CatImage(cat: cat, accent: accent),
                            footer: _CardFooter(
                              cat: cat,
                              accent: accent,
                              stars: stars,
                              power: power,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleSide() => setState(() => _showStats = !_showStats);
}

class _CatImage extends StatelessWidget {
  const _CatImage({required this.cat, required this.accent});

  final CollectedCat cat;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return cat.imagePath != null && File(cat.imagePath!).existsSync()
        ? Image.file(
            File(cat.imagePath!),
            fit: BoxFit.cover,
            semanticLabel: 'Photo of ${cat.name}',
          )
        : ColoredBox(
            color: accent.withValues(alpha: .25),
            child: const Center(
              child: Icon(
                Icons.pets_rounded,
                size: 48,
                color: Color(0xFF312E81),
              ),
            ),
          );
  }
}

class _CardFooter extends StatelessWidget {
  const _CardFooter({
    required this.cat,
    required this.accent,
    required this.stars,
    required this.power,
  });

  final CollectedCat cat;
  final Color accent;
  final String stars;
  final int power;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              cat.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            Text(
              cat.breed,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            FittedBox(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    stars,
                    style: const TextStyle(
                      color: Color(0xFFFDE68A),
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: accent),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Text(
                        'PWR $power',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack({super.key, required this.cat, required this.accent});

  final CollectedCat cat;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF1E1147),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFF6D365), width: 5),
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(16),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.pets_rounded, color: accent, size: 42),
              const SizedBox(height: 12),
              Text(
                cat.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              _stat('ATK', cat.attack),
              _stat('DEF', cat.defense),
              _stat('SPD', cat.speed),
              const SizedBox(height: 12),
              const Text(
                'Long press to flip back',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, int value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Text(
      '$label  $value',
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    ),
  );
}
