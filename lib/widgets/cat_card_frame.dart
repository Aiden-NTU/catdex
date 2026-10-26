import 'dart:math' as math;

import 'package:flutter/material.dart';

const catCardFrameAsset = 'assets/art/battle/card_frame.jpg';

bool animationsEnabled(BuildContext context) =>
    !MediaQuery.maybeOf(context)!.disableAnimations;

class CatSticker extends StatelessWidget {
  const CatSticker({
    super.key,
    required this.name,
    this.size = 42,
    this.semanticLabel,
  });

  final String name;
  final double size;
  final String? semanticLabel;

  IconData? get _icon => switch (name) {
    'crown' => Icons.workspace_premium_rounded,
    'bandana' => Icons.change_history_rounded,
    'sunglasses' => Icons.visibility_rounded,
    'bow' => Icons.brightness_1_rounded,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final icon = _icon;
    if (icon == null) return const SizedBox.shrink();
    return Semantics(
      label: semanticLabel ?? '$name sticker',
      image: true,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFF2E1065).withValues(alpha: 0.88),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFDE68A), width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 5, offset: Offset(0, 2)),
            ],
          ),
          child: Icon(icon, color: const Color(0xFFFDE68A), size: size * .64),
        ),
      ),
    );
  }
}

class FoilSheen extends StatefulWidget {
  const FoilSheen({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.animate = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final bool animate;

  @override
  State<FoilSheen> createState() => _FoilSheenState();
}

class _FoilSheenState extends State<FoilSheen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.animate && animationsEnabled(context)) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = .3;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  painter: _FoilPainter(progress: _controller.value),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FoilPainter extends CustomPainter {
  const _FoilPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final x = (progress * 2 - .5) * size.width;
    final rect = Rect.fromLTWH(x - size.width * .38, 0, size.width * .5, size.height);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          Color(0x1FFFFFFF),
          Color(0x307DD3FC),
          Color(0x28F0ABFC),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.save();
    canvas.translate(x, size.height / 2);
    canvas.rotate(-math.pi / 16);
    canvas.translate(-x, -size.height / 2);
    canvas.drawRect(rect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FoilPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class CatCardFrame extends StatelessWidget {
  const CatCardFrame({
    super.key,
    required this.image,
    required this.footer,
    this.sticker = 'none',
    this.animateFoil = true,
  });

  final Widget image;
  final Widget footer;
  final String sticker;
  final bool animateFoil;

  @override
  Widget build(BuildContext context) {
    return FoilSheen(
      animate: animateFoil,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(catCardFrameAsset),
            fit: BoxFit.fill,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            return Stack(
              children: [
                Positioned(
                  left: w * .105,
                  right: w * .105,
                  top: w * .14,
                  height: constraints.maxHeight * .59,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(w * .07),
                    child: image,
                  ),
                ),
                Positioned(
                  left: w * .105,
                  right: w * .105,
                  bottom: constraints.maxHeight * .055,
                  height: constraints.maxHeight * .18,
                  child: footer,
                ),
                if (sticker != 'none')
                  Positioned(
                    right: w * .11,
                    top: w * .12,
                    child: CatSticker(name: sticker, size: w * .22),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
