import 'match_state.dart';

/// Renderer-neutral animation vocabulary shared by the procedural rig and a
/// future artist-authored Rive state machine.
enum FighterMotion { idle, anticipation, attack, ability, guard, hit, victory }

abstract interface class FighterAnimationAdapter {
  FighterMotion get motion;
  void trigger(TacticalAction action);
  void settle();
}

class ProceduralFighterAnimationAdapter implements FighterAnimationAdapter {
  @override
  FighterMotion motion = FighterMotion.idle;

  @override
  void trigger(TacticalAction action) {
    motion = switch (action) {
      TacticalAction.attack => FighterMotion.attack,
      TacticalAction.ability => FighterMotion.ability,
      TacticalAction.guard => FighterMotion.guard,
      TacticalAction.surrender => FighterMotion.hit,
    };
  }

  @override
  void settle() => motion = FighterMotion.idle;
}

/// Exact state-machine contract expected from an approved `.riv`.
///
/// Keeping this contract separate means a Rive-backed implementation can bind
/// these inputs without changing battle state or shipping a placeholder binary.
class RiveFighterContract {
  const RiveFighterContract._();

  static const stateMachine = 'BattleCat';
  static const motionInput = 'motion';
  static const hitTrigger = 'hit';
  static const victoryTrigger = 'victory';
  static const reducedMotionInput = 'reducedMotion';
}
