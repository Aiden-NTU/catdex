import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../game/battle/breed_types.dart';
import '../../game/battle/cat_skills.dart';
import '../../game/battle/spam_battle_engine.dart';
import '../../models/cat.dart';
import '../../widgets/battle/battle_cat_actor.dart';

/// Spam-tap duel with animated cat sprites and mockup-style HP plaques.
class SpamDuelScreen extends StatefulWidget {
  const SpamDuelScreen({
    super.key,
    required this.mine,
    required this.rival,
    this.difficulty = NpcDifficulty.normal,
  });

  final CollectedCat mine;
  final CollectedCat rival;
  final NpcDifficulty difficulty;

  @override
  State<SpamDuelScreen> createState() => _SpamDuelScreenState();
}

class _SpamDuelScreenState extends State<SpamDuelScreen>
    with TickerProviderStateMixin {
  late final SpamBattleEngine _engine;
  late final AnimationController _playerAnim;
  late final AnimationController _rivalAnim;
  late final AnimationController _impact;
  late final AnimationController _shake;
  late final AnimationController _slash;
  Timer? _ticker;
  final _npcQueue = <SpamHit>[];
  bool _playingNpc = false;
  SkillAnim? _playerMotion;
  SkillAnim? _rivalMotion;
  SkillAnim? _fxMotion;
  int _playerAttackNonce = 0;
  int _rivalAttackNonce = 0;
  String? _banner;
  int? _floatDamage;
  bool _floatOnRival = true;
  bool _critFlash = false;
  int _seenHits = 0;

  @override
  void initState() {
    super.initState();
    _engine = SpamBattleEngine(
      player: widget.mine,
      rival: widget.rival,
      difficulty: widget.difficulty,
    );
    _playerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _rivalAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _impact = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _engine.tick(DateTime.now());
      _syncNpcHits();
      if (mounted) setState(() {});
    });
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _engine.start();
      setState(() => _banner = 'TAP THE RIVAL!');
    });
  }

  void _syncNpcHits() {
    if (_engine.hits.length <= _seenHits) return;
    for (final hit in _engine.hits.skip(_seenHits)) {
      if (!hit.actorIsPlayer) _npcQueue.add(hit);
    }
    _seenHits = _engine.hits.length;
    if (!_playingNpc) unawaited(_drainNpcQueue());
  }

  Future<void> _drainNpcQueue() async {
    if (_playingNpc) return;
    _playingNpc = true;
    while (_npcQueue.isNotEmpty && mounted) {
      final hit = _npcQueue.removeAt(0);
      _playHitFx(hit, onRival: false);
      await Future<void>.delayed(const Duration(milliseconds: 420));
    }
    _playingNpc = false;
  }

  void _playHitFx(SpamHit hit, {required bool onRival}) {
    if (onRival) {
      _playerMotion = hit.skill.anim;
      _playerAttackNonce++;
      unawaited(_playerAnim.forward(from: 0));
    } else {
      _rivalMotion = hit.skill.anim;
      _rivalAttackNonce++;
      unawaited(_rivalAnim.forward(from: 0));
    }
    _fxMotion = hit.skill.anim;
    _floatDamage = hit.damage;
    _floatOnRival = onRival;
    _critFlash = hit.crit;
    _banner = hit.crit
        ? 'CRITICAL!'
        : hit.effectiveness > 1.1
        ? 'Super effective!'
        : hit.effectiveness < 0.9
        ? 'Not very effective…'
        : hit.skill.name;
    unawaited(_impact.forward(from: 0));
    unawaited(_slash.forward(from: 0));
    unawaited(_shake.forward(from: 0));
    HapticFeedback.mediumImpact();
    setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _playerAnim.dispose();
    _rivalAnim.dispose();
    _impact.dispose();
    _shake.dispose();
    _slash.dispose();
    super.dispose();
  }

  Future<void> _onRivalTap() async {
    if (_engine.phase != SpamPhase.playerWindow || _engine.finished) return;
    HapticFeedback.selectionClick();
    final hit = _engine.playerTap(DateTime.now());
    if (hit == null) {
      setState(() {});
      return;
    }
    _seenHits = _engine.hits.length;
    _playHitFx(hit, onRival: true);
  }

  int _displayHp(int hp) => (hp * 28).clamp(0, 2800);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final cardW = math.min(size.width * 0.40, 210.0);
    final remaining = _engine.windowEnds == null
        ? 0.0
        : (_engine.windowEnds!.difference(DateTime.now()).inMilliseconds /
                  _engine.window.inMilliseconds)
              .clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0614),
      body: AnimatedBuilder(
        animation: _shake,
        builder: (context, child) {
          final shake = _shake.isAnimating
              ? math.sin(_shake.value * math.pi * 8) * 6 * (1 - _shake.value)
              : 0.0;
          return Transform.translate(offset: Offset(shake, 0), child: child);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/art/battle/rooftop_arena.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const ColoredBox(color: Color(0xFF1A1028)),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x55000000), Color(0xEE0B0614)],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _HpPlaque(
                            name: widget.mine.name,
                            temper: _engine.playerTemper.label,
                            hp: _displayHp(_engine.playerHp),
                            maxHp: 2800,
                            accent: _parse(widget.mine.accentColor),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white54,
                            size: 22,
                          ),
                        ),
                        Expanded(
                          child: _HpPlaque(
                            name: widget.rival.name,
                            temper: _engine.rivalTemper.label,
                            hp: _displayHp(_engine.rivalHp),
                            maxHp: 2800,
                            accent: _parse(widget.rival.accentColor),
                            alignEnd: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_engine.phase == SpamPhase.playerWindow ||
                      _engine.phase == SpamPhase.npcWindow)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(48, 10, 48, 0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: remaining,
                          minHeight: 7,
                          backgroundColor: Colors.white24,
                          color: _engine.phase == SpamPhase.playerWindow
                              ? const Color(0xFFFBBF24)
                              : const Color(0xFFEF4444),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _SpriteCard(
                              width: cardW,
                              accent: _parse(widget.mine.accentColor),
                              tilt: -0.12,
                              facingRight: true,
                              motion: _playerMotion,
                              anim: _playerAnim,
                              attackNonce: _playerAttackNonce,
                              darkCoat: false,
                              glowing: _engine.phase == SpamPhase.playerWindow,
                            ),
                            GestureDetector(
                              onTap: _onRivalTap,
                              child: _SpriteCard(
                                width: cardW,
                                accent: _parse(widget.rival.accentColor),
                                tilt: 0.12,
                                facingRight: false,
                                motion: _rivalMotion,
                                anim: _rivalAnim,
                                attackNonce: _rivalAttackNonce,
                                darkCoat: true,
                                glowing:
                                    _engine.phase == SpamPhase.playerWindow,
                                showTapHint:
                                    _engine.phase == SpamPhase.playerWindow &&
                                    !_engine.finished,
                              ),
                            ),
                          ],
                        ),
                        // Skill FX + damage float (Pokémon-style readable hit)
                        AnimatedBuilder(
                          animation: Listenable.merge([_impact, _slash]),
                          builder: (context, _) {
                            if (!_impact.isAnimating &&
                                !_slash.isAnimating &&
                                _impact.value == 0) {
                              return const SizedBox.shrink();
                            }
                            final t = Curves.easeOut.transform(_impact.value);
                            final slashT = Curves.easeInOut.transform(
                              _slash.value,
                            );
                            final burstX = _floatOnRival
                                ? size.width * 0.68
                                : size.width * 0.32;
                            return Positioned(
                              left: burstX - 110,
                              top: size.height * 0.24,
                              child: SizedBox(
                                width: 220,
                                height: 220,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    CustomPaint(
                                      size: const Size(220, 220),
                                      painter: _SkillFxPainter(
                                        progress: slashT,
                                        anim: _fxMotion,
                                        crit: _critFlash,
                                        towardRight: _floatOnRival,
                                      ),
                                    ),
                                    Opacity(
                                      opacity: (1 - t * 0.8).clamp(0, 1),
                                      child: Transform.translate(
                                        offset: Offset(0, -t * 48),
                                        child: Transform.scale(
                                          scale: 0.85 + t * 0.35,
                                          child: Text(
                                            _floatDamage == null
                                                ? ''
                                                : '-$_floatDamage',
                                            style: TextStyle(
                                              color: _critFlash
                                                  ? const Color(0xFFFDE68A)
                                                  : Colors.white,
                                              fontSize: _critFlash ? 64 : 50,
                                              fontWeight: FontWeight.w900,
                                              height: 1,
                                              shadows: const [
                                                Shadow(
                                                  blurRadius: 18,
                                                  color: Colors.black,
                                                ),
                                                Shadow(
                                                  blurRadius: 4,
                                                  color: Color(0xFFF59E0B),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        if (_banner != null)
                          Positioned(
                            bottom: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFFBBF24),
                                ),
                              ),
                              child: Text(
                                _banner!,
                                style: const TextStyle(
                                  color: Color(0xFFFBBF24),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      _engine.finished
                          ? (_engine.phase == SpamPhase.victory
                                ? 'Victory!'
                                : 'Defeat')
                          : _engine.phase == SpamPhase.playerWindow
                          ? 'Spam the rival — Scratch always ready · Pounce & Special on cooldown'
                          : 'Rival flurry…',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  if (_engine.finished)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Back to map'),
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

  Color _parse(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.tryParse('FF$h', radix: 16) ?? 0xFFFDBA74);
  }
}

class _HpPlaque extends StatelessWidget {
  const _HpPlaque({
    required this.name,
    required this.temper,
    required this.hp,
    required this.maxHp,
    required this.accent,
    this.alignEnd = false,
  });

  final String name;
  final String temper;
  final int hp;
  final int maxHp;
  final Color accent;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        value: (hp / maxHp).clamp(0, 1),
        minHeight: 11,
        backgroundColor: const Color(0xFF44403C),
        color: const Color(0xFFFBBF24),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: const Color(0xF014100E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF78716C), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!alignEnd) ...[
                _crest(accent),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: alignEnd ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 1.1,
                    fontFamily: 'serif',
                  ),
                ),
              ),
              if (alignEnd) ...[
                const SizedBox(width: 8),
                _crest(accent),
              ],
            ],
          ),
          Text(
            temper,
            style: TextStyle(
              color: accent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          bar,
          const SizedBox(height: 4),
          Text(
            'HP $hp',
            style: const TextStyle(
              color: Color(0xFFFDE68A),
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _crest(Color accent) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.35),
        border: Border.all(color: accent, width: 1.5),
      ),
      child: Icon(Icons.pets, size: 12, color: accent),
    );
  }
}

class _SpriteCard extends StatelessWidget {
  const _SpriteCard({
    required this.width,
    required this.accent,
    required this.tilt,
    required this.facingRight,
    required this.anim,
    required this.attackNonce,
    this.motion,
    this.darkCoat = false,
    this.glowing = false,
    this.showTapHint = false,
  });

  final double width;
  final Color accent;
  final double tilt;
  final bool facingRight;
  final AnimationController anim;
  final int attackNonce;
  final SkillAnim? motion;
  final bool darkCoat;
  final bool glowing;
  final bool showTapHint;

  @override
  Widget build(BuildContext context) {
    final height = width / 0.72;
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final t = anim.value;
        final extraTilt = motion == SkillAnim.pounce
            ? math.sin(t * math.pi) * 0.1 * (facingRight ? 1 : -1)
            : 0.0;
        return Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(tilt)
            ..rotateZ(extraTilt),
          child: child,
        );
      },
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A2030), Color(0xFF120C18)],
          ),
          border: Border.all(
            color: glowing ? const Color(0xFFFBBF24) : accent,
            width: glowing ? 4 : 3,
          ),
          boxShadow: [
            BoxShadow(
              color: (glowing ? const Color(0xFFFBBF24) : accent)
                  .withValues(alpha: glowing ? 0.55 : 0.3),
              blurRadius: glowing ? 28 : 14,
              spreadRadius: glowing ? 2 : 0,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Soft floor glow behind sprite
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: height * 0.35,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        accent.withValues(alpha: 0),
                        accent.withValues(alpha: 0.25),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 20),
                child: AnimatedBuilder(
                  animation: anim,
                  builder: (context, _) => BattleCatActor(
                    facingRight: facingRight,
                    attackProgress: anim.isAnimating ? anim.value : 0,
                    motion: motion,
                    attackNonce: attackNonce,
                    darkCoat: darkCoat,
                    // Esoteric Spine skeletal runtime (pose attachments + bones).
                    useSpine: true,
                  ),
                ),
              ),
              if (showTapHint)
                const Positioned(
                  top: 10,
                  right: 10,
                  child: Icon(
                    Icons.touch_app,
                    color: Color(0xFFFDE68A),
                    size: 26,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Distinct Pokémon-style hit FX per skill anim.
class _SkillFxPainter extends CustomPainter {
  _SkillFxPainter({
    required this.progress,
    required this.anim,
    required this.crit,
    required this.towardRight,
  });

  final double progress;
  final SkillAnim? anim;
  final bool crit;
  final bool towardRight;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final alpha = (1 - progress * 0.85).clamp(0.0, 1.0);
    final dir = towardRight ? 1.0 : -1.0;

    switch (anim) {
      case SkillAnim.scratch:
        _slashArcs(canvas, c, size, alpha, dir, 3);
      case SkillAnim.pounce:
        _speedLines(canvas, c, size, alpha, dir);
        _starburst(canvas, c, size, alpha, rays: 10);
      case SkillAnim.special:
        _starburst(canvas, c, size, alpha, rays: 16);
        _ring(canvas, c, size.shortestSide * (0.2 + progress * 0.5), alpha);
      case SkillAnim.flurry:
        _slashArcs(canvas, c, size, alpha, dir, 5);
        _ring(canvas, c, size.shortestSide * (0.15 + progress * 0.35), alpha);
      case null:
        _starburst(canvas, c, size, alpha, rays: 8);
    }

    if (crit) {
      _ring(canvas, c, size.shortestSide * (0.3 + progress * 0.4), alpha);
    }
  }

  void _slashArcs(
    Canvas canvas,
    Offset c,
    Size size,
    double alpha,
    double dir,
    int count,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: alpha);
    for (var i = 0; i < count; i++) {
      final y = c.dy - 40 + i * 22.0;
      final lean = (i - count / 2) * 0.15;
      final path = Path()
        ..moveTo(c.dx - dir * 70, y - 10)
        ..quadraticBezierTo(
          c.dx + dir * 10,
          y + lean * 40 + progress * 20,
          c.dx + dir * (40 + progress * 50),
          y + 30,
        );
      canvas.drawPath(path, paint);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFFDE68A).withValues(alpha: alpha * 0.9),
      );
    }
  }

  void _speedLines(
    Canvas canvas,
    Offset c,
    Size size,
    double alpha,
    double dir,
  ) {
    final paint = Paint()
      ..strokeWidth = 3
      ..color = Colors.white.withValues(alpha: alpha);
    for (var i = 0; i < 7; i++) {
      final y = c.dy - 50 + i * 16.0;
      canvas.drawLine(
        Offset(c.dx - dir * (20 + progress * 40), y),
        Offset(c.dx + dir * (30 + progress * 60), y + 4),
        paint,
      );
    }
  }

  void _starburst(
    Canvas canvas,
    Offset c,
    Size size,
    double alpha, {
    required int rays,
  }) {
    final r = size.shortestSide * 0.12 + progress * size.shortestSide * 0.4;
    for (var i = 0; i < rays; i++) {
      final a = i * (math.pi * 2 / rays) + progress;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      canvas.drawCircle(
        p,
        3 + (1 - progress) * 6,
        Paint()
          ..color = (crit ? const Color(0xFFFDE68A) : const Color(0xFFFBBF24))
              .withValues(alpha: alpha),
      );
    }
  }

  void _ring(Canvas canvas, Offset c, double r, double alpha) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Colors.white.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(covariant _SkillFxPainter old) =>
      old.progress != progress ||
      old.anim != anim ||
      old.crit != crit ||
      old.towardRight != towardRight;
}
