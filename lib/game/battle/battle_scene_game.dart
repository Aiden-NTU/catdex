import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'fighter_animation_adapter.dart';
import 'match_state.dart';

/// Cinematic card duel field — photo cards slam like Master Duel, not stick cats.
class BattleSceneGame extends FlameGame {
  BattleSceneGame({
    required this.arenaAsset,
    required this.playerName,
    required this.opponentName,
    this.playerImagePath,
    this.opponentImagePath,
    this.playerAccent = const Color(0xFFFDBA74),
    this.opponentAccent = const Color(0xFFEF4444),
    this.reducedMotion = false,
    this.lowPower = false,
  });

  final String arenaAsset;
  final String playerName;
  final String opponentName;
  final String? playerImagePath;
  final String? opponentImagePath;
  final Color playerAccent;
  final Color opponentAccent;
  final bool reducedMotion;
  final bool lowPower;

  ui.Image? _arena;
  ui.Image? _playerArt;
  ui.Image? _opponentArt;
  double _time = 0;
  double _impact = 0;
  double _dash = 0;
  double _cutIn = 0;
  double _finish = 0;
  bool _playerAttacks = true;
  int? _damage;
  TacticalAction _lastAction = TacticalAction.attack;
  final FighterAnimationAdapter animation = ProceduralFighterAnimationAdapter();
  final _particles = <_Spark>[];
  final _random = math.Random(7);

  @override
  Future<void> onLoad() async {
    images.prefix = '';
    _arena = await images.load(arenaAsset);
    _playerArt = await _loadOptional(playerImagePath);
    _opponentArt = await _loadOptional(opponentImagePath);
    if (!reducedMotion) _cutIn = 1.15;
  }

  Future<ui.Image?> _loadOptional(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      if (path.startsWith('assets/')) {
        return await images.load(path);
      }
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } on Object {
      return null;
    }
  }

  void playEvent(BattleEvent event, {required String playerCardId}) {
    _playerAttacks = event.actorCardId == playerCardId;
    _damage = event.damage == 0 ? null : event.damage;
    _lastAction = event.action;
    animation.trigger(event.action);
    _dash = reducedMotion ? .18 : .78;
    _impact = reducedMotion ? .12 : .48;
    if (event.action == TacticalAction.attack && !reducedMotion) {
      _cutIn = math.max(_cutIn, 0.55);
    }
    if (!lowPower) {
      for (var i = 0; i < (reducedMotion ? 6 : 22); i++) {
        _particles.add(
          _Spark(
            angle: _random.nextDouble() * math.pi * 2,
            speed: 40 + _random.nextDouble() * 110,
            life: .3 + _random.nextDouble() * .4,
          ),
        );
      }
    }
  }

  void playFinish() {
    if (!reducedMotion) _finish = 0.9;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    _dash = math.max(0, _dash - dt);
    _impact = math.max(0, _impact - dt);
    _cutIn = math.max(0, _cutIn - dt);
    _finish = math.max(0, _finish - dt);
    if (_dash == 0 && _impact == 0) animation.settle();
    for (final particle in _particles) {
      particle.age += dt;
    }
    _particles.removeWhere((particle) => particle.age >= particle.life);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final bounds = Rect.fromLTWH(0, 0, size.x, size.y);
    final arena = _arena;
    if (arena != null) {
      paintImage(canvas: canvas, rect: bounds, image: arena, fit: BoxFit.cover);
    } else {
      canvas.drawRect(bounds, Paint()..color = const Color(0xff1a1420));
    }
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x33000000), Color(0xcc0a0610)],
        ).createShader(bounds),
    );

    final shake = _impact > 0 && !reducedMotion
        ? math.sin(_time * 78) * 7 * (_impact / .48)
        : 0.0;
    canvas.save();
    canvas.translate(shake, 0);

    final ground = size.y * .72;
    final travel = _dash > 0
        ? math.sin((.78 - _dash).clamp(0, .78) / .78 * math.pi) * size.x * .2
        : 0.0;
    final playerX = size.x * .28 + (_playerAttacks ? travel : 0);
    final rivalX = size.x * .72 - (_playerAttacks ? 0 : travel);
    final cardW = size.x * .28;
    final cardH = cardW / 0.72;

    if (_lastAction == TacticalAction.ability && _dash > 0) {
      final progress = (1 - _dash / .78).clamp(0.0, 1.0);
      final fromX = _playerAttacks ? playerX : rivalX;
      final toX = _playerAttacks ? rivalX : playerX;
      final orb = Offset(
        fromX + (toX - fromX) * progress,
        ground - cardH * .35 - math.sin(progress * math.pi) * 55,
      );
      final accent = _playerAttacks ? playerAccent : opponentAccent;
      canvas.drawCircle(
        orb,
        14 + math.sin(_time * 22) * 3,
        Paint()
          ..shader = RadialGradient(
            colors: [Colors.white, accent, accent.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: orb, radius: 28)),
      );
    }

    _drawCard(
      canvas,
      center: Offset(playerX, ground),
      width: cardW,
      height: cardH,
      art: _playerArt,
      name: playerName,
      accent: playerAccent,
      tilt: -0.08 + (_playerAttacks && _dash > 0 ? -0.12 : 0),
      guarding: !_playerAttacks &&
          _lastAction == TacticalAction.guard &&
          _impact > 0,
    );
    _drawCard(
      canvas,
      center: Offset(rivalX, ground),
      width: cardW,
      height: cardH,
      art: _opponentArt,
      name: opponentName,
      accent: opponentAccent,
      tilt: 0.08 + (!_playerAttacks && _dash > 0 ? 0.12 : 0),
      guarding: _playerAttacks &&
          _lastAction == TacticalAction.guard &&
          _impact > 0,
      flash: _impact > 0 && _playerAttacks,
    );

    if (_impact > 0) {
      final center = Offset(
        _playerAttacks ? rivalX : playerX,
        ground - cardH * .35,
      );
      for (final spark in _particles) {
        final distance = spark.speed * spark.age;
        final alpha = (1 - spark.age / spark.life).clamp(0.0, 1.0);
        canvas.drawCircle(
          center +
              Offset(math.cos(spark.angle), math.sin(spark.angle)) * distance,
          3,
          Paint()..color = Color.fromRGBO(255, 230, 140, alpha),
        );
      }
      canvas.drawCircle(
        center,
        28 + (1 - _impact / .48) * 40,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white.withValues(alpha: _impact / .48),
      );
      if (_damage case final damage?) {
        final text = TextPainter(
          text: TextSpan(
            text: '-$damage',
            style: const TextStyle(
              color: Color(0xfffff1a8),
              fontSize: 36,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(blurRadius: 8, color: Colors.black)],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(
          canvas,
          center + Offset(-text.width / 2, -90 - (1 - _impact / .48) * 30),
        );
      }
    }
    canvas.restore();

    if (_cutIn > 0) {
      _drawCutIn(canvas, bounds);
    }
    if (_finish > 0) {
      canvas.drawRect(
        bounds,
        Paint()..color = Colors.white.withValues(alpha: _finish * 0.55),
      );
    }
  }

  void _drawCutIn(Canvas canvas, Rect bounds) {
    final t = (_cutIn / 1.15).clamp(0.0, 1.0);
    final art = _playerAttacks ? _playerArt : _opponentArt;
    final name = _playerAttacks ? playerName : opponentName;
    final accent = _playerAttacks ? playerAccent : opponentAccent;
    canvas.drawRect(
      bounds,
      Paint()..color = const Color(0xEE0A0610).withValues(alpha: t * 0.92),
    );
    final cardW = bounds.width * 0.55;
    final cardH = cardW / 0.72;
    final scale = 0.85 + (1 - t) * 0.25;
    canvas.save();
    canvas.translate(bounds.center.dx, bounds.center.dy - 20);
    canvas.scale(scale);
    _drawCard(
      canvas,
      center: Offset.zero,
      width: cardW,
      height: cardH,
      art: art,
      name: name,
      accent: accent,
      tilt: -0.04,
      guarding: false,
    );
    canvas.restore();
    final label = TextPainter(
      text: TextSpan(
        text: name.toUpperCase(),
        style: TextStyle(
          color: accent,
          fontSize: 28,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
          shadows: const [Shadow(blurRadius: 12, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: bounds.width - 40);
    label.paint(
      canvas,
      Offset((bounds.width - label.width) / 2, bounds.height * 0.78),
    );
  }

  void _drawCard(
    Canvas canvas, {
    required Offset center,
    required double width,
    required double height,
    required ui.Image? art,
    required String name,
    required Color accent,
    required double tilt,
    required bool guarding,
    bool flash = false,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy - height * 0.42);
    canvas.rotate(tilt);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: width,
      height: height,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(14));
    canvas.drawRRect(
      rrect.shift(const Offset(4, 8)),
      Paint()..color = Colors.black54,
    );
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF1C1917));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = accent,
    );
    final photo = rect.deflate(8);
    final photoR = RRect.fromRectAndRadius(photo, const Radius.circular(8));
    canvas.save();
    canvas.clipRRect(photoR);
    if (art != null) {
      paintImage(canvas: canvas, rect: photo, image: art, fit: BoxFit.cover);
    } else {
      canvas.drawRect(photo, Paint()..color = accent.withValues(alpha: 0.35));
      canvas.drawOval(
        Rect.fromCenter(
          center: photo.center,
          width: width * 0.45,
          height: width * 0.38,
        ),
        Paint()..color = accent,
      );
    }
    if (flash) {
      canvas.drawRect(
        photo,
        Paint()..color = Colors.white.withValues(alpha: 0.55),
      );
    }
    canvas.restore();

    final band = Rect.fromLTWH(
      rect.left + 6,
      rect.bottom - height * 0.18,
      width - 12,
      height * 0.14,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(band, const Radius.circular(6)),
      Paint()..color = const Color(0xEE0C0A09),
    );
    final label = TextPainter(
      text: TextSpan(
        text: name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: band.width - 8);
    label.paint(
      canvas,
      Offset(band.left + 4, band.center.dy - label.height / 2),
    );

    if (guarding) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = const Color(0xFF38BDF8).withValues(alpha: 0.85),
      );
      canvas.drawCircle(
        Offset.zero,
        width * 0.42,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0x8838BDF8),
      );
    }
    canvas.restore();
  }
}

class _Spark {
  _Spark({required this.angle, required this.speed, required this.life});
  final double angle;
  final double speed;
  final double life;
  double age = 0;
}
