import 'package:flutter/material.dart';

class GateHintBanner extends StatelessWidget {
  const GateHintBanner({
    super.key,
    required this.hint,
    required this.ready,
  });

  final String hint;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: ready
            ? const Color(0xFF166534).withValues(alpha: 0.92)
            : const Color(0xFF1C1917).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready ? Icons.check_circle : Icons.pets,
            color: ready ? const Color(0xFF86EFAC) : const Color(0xFFFDBA74),
            size: 20,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              hint,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
