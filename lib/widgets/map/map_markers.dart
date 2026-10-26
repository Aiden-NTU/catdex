import 'dart:math' as math;

import 'package:flutter/material.dart';

class UserMapPointer extends StatefulWidget {
  const UserMapPointer({super.key, this.heading});

  final double? heading;

  @override
  State<UserMapPointer> createState() => _UserMapPointerState();
}

class _UserMapPointerState extends State<UserMapPointer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final value = Curves.easeOut.transform(_pulse.value);
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 34 + value * 28,
              height: 34 + value * 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF97316)
                    .withValues(alpha: .28 * (1 - value)),
              ),
            ),
            if (widget.heading case final heading?)
              Transform.rotate(
                angle: heading * math.pi / 180,
                child: const Align(
                  alignment: Alignment.topCenter,
                  child: Icon(
                    Icons.navigation,
                    color: Colors.white,
                    size: 27,
                    shadows: [Shadow(blurRadius: 5, color: Colors.black)],
                  ),
                ),
              ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: const Color(0xFFF97316),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 8),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Icon-only wild cat — name lives in Nearby / tap sheet, not on the map.
class WildCatMapMarker extends StatefulWidget {
  const WildCatMapMarker({
    super.key,
    required this.inRange,
    required this.onTap,
  });

  final bool inRange;
  final VoidCallback onTap;

  @override
  State<WildCatMapMarker> createState() => _WildCatMapMarkerState();
}

class _WildCatMapMarkerState extends State<WildCatMapMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.inRange ? 'Catchable cat' : 'Cat nearby',
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _bob,
          builder: (context, child) {
            final dy = widget.inRange ? (_bob.value - 0.5) * 10 : 0.0;
            return Transform.translate(offset: Offset(0, dy), child: child);
          },
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: widget.inRange
                  ? const Color(0xFFF97316)
                  : const Color(0xFFEA580C).withValues(alpha: 0.85),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3.5),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4)),
              ],
            ),
            child: Icon(
              Icons.pets,
              color: widget.inRange ? Colors.white : Colors.white70,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}

class RivalMapMarker extends StatelessWidget {
  const RivalMapMarker({
    super.key,
    required this.inRange,
    required this.onTap,
  });

  final bool inRange;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: inRange ? 'Challenge encounter' : 'Encounter nearby',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: inRange ? const Color(0xFFEF4444) : const Color(0xFF991B1B),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3.5),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4)),
            ],
          ),
          child: const Icon(Icons.sports_mma, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}

class LandmarkHubMarker extends StatelessWidget {
  const LandmarkHubMarker({
    super.key,
    required this.kind,
    required this.progress,
    required this.onTap,
  });

  final String kind;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (kind) {
      'cat_cafe_rally' => const Color(0xFFF59E0B),
      'cardboard_fortress' => const Color(0xFFA78BFA),
      'laser_pointer_chase' => const Color(0xFF22D3EE),
      _ => const Color(0xFFFDBA74),
    };
    return Semantics(
      button: true,
      label: 'Landmark event',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress.clamp(0, 1),
                strokeWidth: 3.5,
                color: color,
                backgroundColor: Colors.white54,
              ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 8),
                  ],
                ),
                child: Icon(Icons.place, color: color, size: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EventMapMarker extends StatelessWidget {
  const EventMapMarker({
    super.key,
    required this.kind,
    required this.progress,
    required this.onTap,
    this.count = 1,
  });

  final String kind;
  final double progress;
  final VoidCallback onTap;
  final int count;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (kind) {
      'cat_cafe_rally' => (Icons.local_cafe, const Color(0xFFF59E0B)),
      'cardboard_fortress' => (Icons.castle, const Color(0xFFA78BFA)),
      'laser_pointer_chase' => (Icons.adjust, const Color(0xFF22D3EE)),
      _ => (Icons.pets, const Color(0xFFFDBA74)),
    };
    return Semantics(
      button: true,
      label: count > 1 ? '$count community events' : 'Community event',
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 54,
              height: 54,
              child: CircularProgressIndicator(
                value: progress.clamp(0, 1),
                strokeWidth: 4,
                color: color,
                backgroundColor: Colors.black26,
              ),
            ),
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: color),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 8),
                ],
              ),
              child: Icon(icon, color: color),
            ),
            if (count > 1)
              Positioned(
                right: -4,
                top: -5,
                child: CircleAvatar(
                  radius: 11,
                  backgroundColor: color,
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
