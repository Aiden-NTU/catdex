import 'package:flutter/material.dart';
import 'package:spine_flutter/spine_flutter.dart' hide Color;

import '../../game/battle/cat_skills.dart';

/// Spine-rigged battle cat (Esoteric Spine — industry 2D skeletal standard).
class SpineBattleCat extends StatefulWidget {
  const SpineBattleCat({
    super.key,
    required this.facingRight,
    this.motion,
    this.attackNonce = 0,
    this.darkCoat = false,
    this.onFailed,
  });

  final bool facingRight;
  final SkillAnim? motion;
  final int attackNonce;
  final bool darkCoat;
  final VoidCallback? onFailed;

  @override
  State<SpineBattleCat> createState() => _SpineBattleCatState();
}

class _SpineBattleCatState extends State<SpineBattleCat> {
  late final SpineWidgetController _controller;
  bool _ready = false;
  bool _failed = false;

  String get _folder => widget.darkCoat ? 'cat_black' : 'cat_tabby';
  String get _atlas => 'assets/battle/spine/$_folder/cat-pma.atlas';
  String get _skel => 'assets/battle/spine/$_folder/cat-pro.json';

  @override
  void initState() {
    super.initState();
    _controller = SpineWidgetController(
      onInitialized: (c) {
        try {
          c.skeleton.scaleX = widget.facingRight ? 1.0 : -1.0;
          c.animationStateData.defaultMix = 0.12;
          c.animationState.setAnimation(0, 'idle', true);
          _ready = true;
          _playMotion(widget.motion);
        } on Object catch (e, st) {
          debugPrint('SpineBattleCat init failed: $e\n$st');
          _fail();
        }
      },
    );
  }

  void _fail() {
    if (_failed) return;
    _failed = true;
    widget.onFailed?.call();
  }

  @override
  void didUpdateWidget(covariant SpineBattleCat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_ready || _failed) return;
    try {
      if (oldWidget.facingRight != widget.facingRight) {
        _controller.skeleton.scaleX = widget.facingRight ? 1.0 : -1.0;
      }
      if (oldWidget.attackNonce != widget.attackNonce ||
          oldWidget.motion != widget.motion) {
        _playMotion(widget.motion);
      }
    } on Object catch (e) {
      debugPrint('SpineBattleCat update failed: $e');
      _fail();
    }
  }

  void _playMotion(SkillAnim? motion) {
    if (!_ready || _failed) return;
    final name = switch (motion) {
      SkillAnim.scratch => 'scratch',
      SkillAnim.pounce => 'pounce',
      SkillAnim.special => 'special',
      SkillAnim.flurry => 'flurry',
      null => null,
    };
    if (name == null) {
      _controller.animationState.setAnimation(0, 'idle', true);
      return;
    }
    final entry = _controller.animationState.setAnimation(0, name, false);
    entry.setListener((type, entry, event) {
      if (type == EventType.complete) {
        _controller.animationState.setAnimation(0, 'idle', true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    return SpineWidget.fromAsset(
      _atlas,
      _skel,
      _controller,
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
    );
  }
}
