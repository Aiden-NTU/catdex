import 'dart:io';

import 'package:flutter/material.dart';

import '../models/cat.dart';
import '../widgets/cat_card_frame.dart';

/// Short hatch → card settle after a successful catch.
class HatchRevealScreen extends StatefulWidget {
  const HatchRevealScreen({
    super.key,
    required this.cat,
    this.onDone,
  });

  final CollectedCat cat;
  final VoidCallback? onDone;

  @override
  State<HatchRevealScreen> createState() => _HatchRevealScreenState();
}

class _HatchRevealScreenState extends State<HatchRevealScreen>
    with TickerProviderStateMixin {
  late final AnimationController _crack = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await _crack.forward();
    if (!mounted) return;
    await _reveal.forward();
  }

  @override
  void dispose() {
    _crack.dispose();
    _reveal.dispose();
    super.dispose();
  }

  void _finish() {
    final done = widget.onDone;
    if (done != null) {
      done();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.cat;
    final image = cat.imagePath != null && File(cat.imagePath!).existsSync()
        ? Image.file(File(cat.imagePath!), fit: BoxFit.cover)
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0A09),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              AnimatedBuilder(
                animation: Listenable.merge([_crack, _reveal]),
                builder: (context, _) {
                  final cracking = _crack.value < 1;
                  final scale = cracking
                      ? 0.55 + _crack.value * 0.2
                      : 0.75 + Curves.easeOutBack.transform(_reveal.value) * 0.25;
                  final glow = cracking
                      ? _crack.value
                      : 0.4 + _reveal.value * 0.6;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFDBA74)
                                .withValues(alpha: 0.35 * glow),
                            blurRadius: 48 * glow,
                            spreadRadius: 8 * glow,
                          ),
                        ],
                      ),
                      child: AspectRatio(
                        aspectRatio: 0.72,
                        child: cracking
                            ? _Egg(progress: _crack.value)
                            : Opacity(
                                opacity: _reveal.value.clamp(0, 1),
                                child: CatCardFrame(
                                  image: image ??
                                      const ColoredBox(
                                        color: Color(0xFF44403C),
                                        child: Center(
                                          child: Icon(
                                            Icons.pets,
                                            size: 64,
                                            color: Color(0xFFFDBA74),
                                          ),
                                        ),
                                      ),
                                  footer: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        cat.name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      Text(
                                        '${'★' * cat.stars}'
                                        '${'☆' * (5 - cat.stars)}'
                                        '  ·  PWR ${cat.battlePower}',
                                        style: const TextStyle(
                                          color: Color(0xFFFDE68A),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 28),
              Text(
                _reveal.value > 0.5 ? 'Hatched into your Cat Den' : 'Hatching…',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                cat.breed,
                style: const TextStyle(color: Colors.white54),
              ),
              const Spacer(),
              AnimatedBuilder(
                animation: _reveal,
                builder: (context, _) => FilledButton(
                  onPressed: _reveal.value > 0.85 ? _finish : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFDBA74),
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text(
                    'Open Cat Den',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Egg extends StatelessWidget {
  const _Egg({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _EggPainter(progress: progress),
      child: const Center(
        child: Icon(Icons.pets, size: 48, color: Color(0xFF292524)),
      ),
    );
  }
}

class _EggPainter extends CustomPainter {
  _EggPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.72,
      height: size.height * 0.86,
    );
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFDE68A), Color(0xFFFDBA74)],
      ).createShader(rect);
    canvas.drawOval(rect, paint);
    final crack = Paint()
      ..color = const Color(0xFF44403C)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(rect.center.dx, rect.top + rect.height * 0.2)
      ..lineTo(
        rect.center.dx - 18 * progress,
        rect.center.dy - 10,
      )
      ..lineTo(rect.center.dx + 12 * progress, rect.center.dy + 8)
      ..lineTo(rect.center.dx, rect.bottom - rect.height * 0.25);
    canvas.drawPath(path, crack);
  }

  @override
  bool shouldRepaint(covariant _EggPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
