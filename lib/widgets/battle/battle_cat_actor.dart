import 'package:flutter/material.dart';

import '../../game/battle/cat_skills.dart';
import 'pose_sheet_battle_cat.dart';
import 'spine_battle_cat.dart';

/// Battle fighter: photorealistic Spine pose plates, optionally driven by the
/// Esoteric Spine skeletal runtime (`spine_flutter`).
class BattleCatActor extends StatefulWidget {
  const BattleCatActor({
    super.key,
    required this.facingRight,
    required this.attackProgress,
    this.motion,
    this.attackNonce = 0,
    this.darkCoat = false,
    this.useSpine = true,
  });

  final bool facingRight;
  final double attackProgress;
  final SkillAnim? motion;
  final int attackNonce;
  final bool darkCoat;
  final bool useSpine;

  @override
  State<BattleCatActor> createState() => _BattleCatActorState();
}

class _BattleCatActorState extends State<BattleCatActor> {
  bool _spineOk = true;

  @override
  Widget build(BuildContext context) {
    final pose = PoseSheetBattleCat(
      facingRight: widget.facingRight,
      attackProgress: widget.attackProgress,
      motion: widget.motion,
      darkCoat: widget.darkCoat,
    );

    if (!widget.useSpine || !_spineOk) return pose;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Always keep pose plates ready underneath (instant fallback).
        pose,
        // Spine draws on top when the skeleton loads; on failure we hide it.
        SpineBattleCat(
          facingRight: widget.facingRight,
          motion: widget.motion,
          attackNonce: widget.attackNonce,
          darkCoat: widget.darkCoat,
          onFailed: () {
            if (!_spineOk) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _spineOk = false);
            });
          },
        ),
      ],
    );
  }
}
