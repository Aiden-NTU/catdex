import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../game/battle/cat_skills.dart';

/// Poseable 2D cat sprite (Pokémon-style body animation, not a flat photo).
class AnimatedCatSprite extends StatefulWidget {
  const AnimatedCatSprite({
    super.key,
    required this.accent,
    required this.facingRight,
    this.motion,
    this.attackProgress = 0,
    this.faceImage,
    this.idle = true,
  });

  final Color accent;
  final bool facingRight;
  final SkillAnim? motion;
  final double attackProgress;
  final ui.Image? faceImage;
  final bool idle;

  @override
  State<AnimatedCatSprite> createState() => _AnimatedCatSpriteState();
}

class _AnimatedCatSpriteState extends State<AnimatedCatSprite>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _idle,
      builder: (context, _) {
        return CustomPaint(
          painter: _CatSpritePainter(
            accent: widget.accent,
            facingRight: widget.facingRight,
            motion: widget.motion,
            attack: widget.attackProgress,
            idle: widget.idle ? _idle.value : 0.5,
            face: widget.faceImage,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _CatSpritePainter extends CustomPainter {
  _CatSpritePainter({
    required this.accent,
    required this.facingRight,
    required this.motion,
    required this.attack,
    required this.idle,
    this.face,
  });

  final Color accent;
  final bool facingRight;
  final SkillAnim? motion;
  final double attack;
  final double idle;
  final ui.Image? face;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    canvas.save();
    canvas.translate(size.width / 2, size.height * 0.62);
    if (!facingRight) canvas.scale(-1, 1);

    var bob = (idle - 0.5) * 6;
    var lunge = 0.0;
    var stretch = 1.0;
    var pawSwing = 0.0;
    var spin = 0.0;
    var flash = 0.0;
    final t = Curves.easeInOut.transform(attack.clamp(0.0, 1.0));

    switch (motion) {
      case SkillAnim.scratch:
        // Quick claw rake — short lunge + hard paw whip
        pawSwing = math.sin(t * math.pi) * 1.8;
        lunge = math.sin(t * math.pi) * s * 0.16;
        bob -= math.sin(t * math.pi) * 6;
        flash = math.sin(t * math.pi);
      case SkillAnim.pounce:
        // Leap arc: crouch → fly → land
        final leap = t < 0.45
            ? Curves.easeOut.transform(t / 0.45)
            : 1 - Curves.easeIn.transform((t - 0.45) / 0.55);
        lunge = leap * s * 0.38;
        stretch = 1 + leap * 0.4;
        bob -= leap * 36;
        pawSwing = leap * 0.6;
        flash = leap;
      case SkillAnim.special:
        // Spin-up power pose then slam forward
        spin = t * math.pi * 2.4;
        flash = math.sin(t * math.pi);
        stretch = 1 + math.sin(t * math.pi) * 0.28;
        lunge = math.sin(t * math.pi) * s * 0.2;
        pawSwing = math.sin(t * math.pi) * 1.1;
      case SkillAnim.flurry:
        // Rapid multi-hit jabs
        pawSwing = math.sin(t * math.pi * 6) * 1.9;
        lunge = math.sin(t * math.pi * 5) * s * 0.18;
        bob -= math.sin(t * math.pi * 4).abs() * 10;
        flash = math.sin(t * math.pi * 6).abs();
      case null:
        break;
    }

    canvas.translate(lunge, bob);
    canvas.rotate(spin * 0.14);
    canvas.scale(1 / stretch, stretch);

    final body = Paint()..color = accent;
    final shade = Paint()..color = Color.lerp(accent, Colors.black, 0.25)!;
    final outline = Paint()
      ..color = const Color(0xFF1C1917)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.03;
    final belly = Paint()..color = Color.lerp(accent, Colors.white, 0.45)!;

    // Tail
    final tail = Path()
      ..moveTo(-s * 0.22, -s * 0.05)
      ..quadraticBezierTo(
        -s * 0.45,
        -s * 0.25 - bob,
        -s * 0.32,
        -s * 0.42 + math.sin(idle * math.pi) * 8,
      );
    canvas.drawPath(
      tail,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.07
        ..strokeCap = StrokeCap.round,
    );

    // Back legs
    _leg(canvas, Offset(-s * 0.12, s * 0.02), s, shade, outline, 0.15);
    _leg(canvas, Offset(s * 0.08, s * 0.02), s, shade, outline, -0.05);

    // Body
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(0, -s * 0.08),
        width: s * 0.55,
        height: s * 0.42,
      ),
      Radius.circular(s * 0.2),
    );
    canvas.drawRRect(bodyRect, body);
    canvas.drawRRect(bodyRect, outline);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(s * 0.04, -s * 0.02),
        width: s * 0.28,
        height: s * 0.22,
      ),
      belly,
    );

    // Front attacking paw
    final pawAngle = -0.4 + pawSwing;
    canvas.save();
    canvas.translate(s * 0.18, -s * 0.05);
    canvas.rotate(pawAngle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, -s * 0.06, s * 0.28, s * 0.12),
        Radius.circular(s * 0.06),
      ),
      body,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, -s * 0.06, s * 0.28, s * 0.12),
        Radius.circular(s * 0.06),
      ),
      outline,
    );
    // Claws
    if (motion == SkillAnim.scratch || motion == SkillAnim.flurry) {
      final claw = Paint()
        ..color = Colors.white
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 3; i++) {
        canvas.drawLine(
          Offset(s * 0.26, -s * 0.04 + i * s * 0.035),
          Offset(s * 0.34 + flash * 8, -s * 0.05 + i * s * 0.035),
          claw,
        );
      }
    }
    canvas.restore();

    // Head
    final head = Offset(s * 0.16, -s * 0.32);
    canvas.drawCircle(head, s * 0.2, body);
    canvas.drawCircle(head, s * 0.2, outline);

    // Ears
    _ear(canvas, head + Offset(-s * 0.12, -s * 0.14), s, body, outline, -0.5);
    _ear(canvas, head + Offset(s * 0.1, -s * 0.16), s, body, outline, 0.35);

    // Face — photo clip or drawn features
    final faceR = s * 0.14;
    if (face != null) {
      canvas.save();
      canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: head, radius: faceR)),
      );
      paintImage(
        canvas: canvas,
        rect: Rect.fromCircle(center: head, radius: faceR),
        image: face!,
        fit: BoxFit.cover,
      );
      canvas.restore();
      canvas.drawCircle(
        head,
        faceR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white70,
      );
    } else {
      _drawnFace(canvas, head, s, flash);
    }

    // Attack VFX bursts
    if (flash > 0.05) {
      final burst = Paint()
        ..color = Colors.white.withValues(alpha: 0.55 * flash)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(
        head + Offset(s * 0.25, 0),
        s * 0.15 + flash * s * 0.2,
        burst,
      );
      if (motion == SkillAnim.special) {
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4 + t * math.pi;
          canvas.drawCircle(
            head + Offset(math.cos(a), math.sin(a)) * s * 0.35 * flash,
            4,
            Paint()..color = Color.lerp(Colors.white, accent, 0.3)!,
          );
        }
      }
      if (motion == SkillAnim.pounce) {
        // Speed lines
        final line = Paint()
          ..color = Colors.white.withValues(alpha: 0.7 * flash)
          ..strokeWidth = 3;
        for (var i = 0; i < 4; i++) {
          final y = -s * 0.2 + i * s * 0.1;
          canvas.drawLine(
            Offset(-s * 0.4, y),
            Offset(-s * 0.15, y + 4),
            line,
          );
        }
      }
    }

    canvas.restore();
  }

  void _ear(
    Canvas canvas,
    Offset tipBase,
    double s,
    Paint fill,
    Paint outline,
    double tilt,
  ) {
    canvas.save();
    canvas.translate(tipBase.dx, tipBase.dy);
    canvas.rotate(tilt);
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(-s * 0.07, -s * 0.16)
      ..lineTo(s * 0.07, -s * 0.02)
      ..close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, outline);
    canvas.restore();
  }

  void _leg(
    Canvas c,
    Offset o,
    double s,
    Paint fill,
    Paint outline,
    double lean,
  ) {
    c.save();
    c.translate(o.dx, o.dy);
    c.rotate(lean);
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(-s * 0.05, 0, s * 0.1, s * 0.2),
      Radius.circular(s * 0.05),
    );
    c.drawRRect(r, fill);
    c.drawRRect(r, outline);
    c.restore();
  }

  void _drawnFace(Canvas canvas, Offset head, double s, double flash) {
    final eyeOpen = 5.0 + flash * 6;
    final white = Paint()..color = Colors.white;
    final pupil = Paint()..color = Colors.black;
    canvas.drawOval(
      Rect.fromCenter(
        center: head + Offset(-s * 0.06, -s * 0.02),
        width: 10,
        height: eyeOpen,
      ),
      white,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: head + Offset(s * 0.06, -s * 0.02),
        width: 10,
        height: eyeOpen,
      ),
      white,
    );
    canvas.drawCircle(head + Offset(-s * 0.06, -s * 0.02), 2.8, pupil);
    canvas.drawCircle(head + Offset(s * 0.06, -s * 0.02), 2.8, pupil);
    // Angry brow / grit mouth
    final brow = Paint()
      ..color = const Color(0xFF1C1917)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      head + Offset(-s * 0.1, -s * 0.08),
      head + Offset(-s * 0.02, -s * 0.05 - flash * 4),
      brow,
    );
    canvas.drawLine(
      head + Offset(s * 0.1, -s * 0.08),
      head + Offset(s * 0.02, -s * 0.05 - flash * 4),
      brow,
    );
    final mouth = Path()
      ..moveTo(head.dx - 8, head.dy + s * 0.06)
      ..quadraticBezierTo(
        head.dx,
        head.dy + s * 0.06 + 6 + flash * 10,
        head.dx + 8,
        head.dy + s * 0.06,
      );
    canvas.drawPath(
      mouth,
      Paint()
        ..color = const Color(0xFF1C1917)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _CatSpritePainter old) =>
      old.attack != attack ||
      old.idle != idle ||
      old.motion != motion ||
      old.accent != accent ||
      old.face != face;
}
