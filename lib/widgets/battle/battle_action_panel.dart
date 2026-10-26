import 'package:flutter/material.dart';

import '../../game/battle/deterministic_rules.dart';
import '../../game/battle/match_state.dart';

class BattleActionPanel extends StatelessWidget {
  const BattleActionPanel({
    super.key,
    required this.actor,
    required this.target,
    required this.enabled,
    required this.onAction,
  });

  final BattleCombatant actor;
  final BattleCombatant target;
  final bool enabled;
  final ValueChanged<TacticalAction> onAction;

  @override
  Widget build(BuildContext context) {
    Widget actionButton(
      TacticalAction action,
      IconData icon,
      String label, {
      bool available = true,
    }) {
      final preview = DeterministicBattleRules.preview(
        actor: actor,
        target: target,
        action: action,
      );
      final semanticsDetail = action == TacticalAction.guard
          ? 'gain energy and reduce next hit'
          : '${preview.$1} to ${preview.$2} damage';
      return Expanded(
        child: Semantics(
          button: true,
          label: '$label, $semanticsDetail',
          child: FilledButton(
            onPressed: enabled && available ? () => onAction(action) : null,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF292524),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF1C1917),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF44403C)),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 28),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        actionButton(TacticalAction.attack, Icons.flash_on, 'Strike'),
        const SizedBox(width: 8),
        actionButton(
          TacticalAction.ability,
          Icons.auto_awesome,
          'Special',
          available: actor.energy >= DeterministicBattleRules.abilityCost,
        ),
        const SizedBox(width: 8),
        actionButton(TacticalAction.guard, Icons.shield, 'Guard'),
      ],
    );
  }
}
