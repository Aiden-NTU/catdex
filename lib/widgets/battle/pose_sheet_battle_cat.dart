import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../game/battle/cat_skills.dart';

/// Photorealistic pose-to-pose battle cat (Spine attachment plates + motion).
class PoseSheetBattleCat extends StatefulWidget {
  const PoseSheetBattleCat({
    super.key,
    required this.facingRight,
    required this.attackProgress,
    this.motion,
    this.darkCoat = false,
  });

  final bool facingRight;
  final double attackProgress;
  final SkillAnim? motion;
  final bool darkCoat;

  @override
  State<PoseSheetBattleCat> createState() => _PoseSheetBattleCatState();
}

class _PoseSheetBattleCatState extends State<PoseSheetBattleCat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  String get _folder => widget.darkCoat ? 'cat_black' : 'cat_tabby';

  String _poseAsset() {
    final t = widget.attackProgress;
    final pose = switch (widget.motion) {
      SkillAnim.scratch => 'scratch',
      SkillAnim.pounce => 'pounce',
      SkillAnim.special => 'special',
      SkillAnim.flurry => t < 0.33
          ? 'scratch'
          : t < 0.66
          ? 'pounce'
          : 'special',
      null => 'idle',
    };
    return 'assets/battle/spine/$_folder/$pose.png';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _idle,
      builder: (context, _) {
        final attack = widget.attackProgress.clamp(0.0, 1.0);
        final t = Curves.easeInOut.transform(attack);
        final dir = widget.facingRight ? 1.0 : -1.0;
        final breath = (_idle.value - 0.5) * 6;

        var dx = 0.0;
        var dy = breath;
        var scaleX = 1.0;
        var scaleY = 1.0;
        var rot = 0.0;

        switch (widget.motion) {
          case SkillAnim.scratch:
            final s = math.sin(t * math.pi);
            dx = s * 28 * dir;
            rot = s * -0.18 * dir;
            scaleX = 1 + s * 0.06;
            dy = breath * 0.3;
          case SkillAnim.pounce:
            final leap = t < 0.45
                ? Curves.easeOut.transform(t / 0.45)
                : 1 - Curves.easeIn.transform((t - 0.45) / 0.55);
            dx = leap * 48 * dir;
            dy = -leap * 36;
            scaleX = 1 + leap * 0.12;
            scaleY = 1 - leap * 0.08;
          case SkillAnim.special:
            rot = t * math.pi * 2 * 0.15 * dir;
            final pulse = math.sin(t * math.pi);
            scaleX = 1 + pulse * 0.18;
            scaleY = 1 + pulse * 0.18;
            dx = pulse * 22 * dir;
            dy = breath * 0.2;
          case SkillAnim.flurry:
            dx = math.sin(t * math.pi * 5) * 30 * dir;
            rot = math.sin(t * math.pi * 4) * 0.2 * dir;
            dy = breath * 0.2;
          case null:
            break;
        }

        return Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            ..translateByDouble(dx, dy, 0, 1)
            ..rotateZ(rot)
            ..scaleByDouble(
              scaleX * (widget.facingRight ? 1 : -1),
              scaleY,
              1,
              1,
            ),
          child: Image.asset(
            _poseAsset(),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Colors.black26),
          ),
        );
      },
    );
  }
}
