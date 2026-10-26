import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../data/cat_repository.dart';
import '../../game/battle/battle_scene_game.dart';
import '../../game/battle/match_state.dart';
import '../../models/cat.dart';
import '../../services/nakama_client.dart';
import '../../services/sync_service.dart';
import '../../widgets/battle/battle_action_panel.dart';

class ImmersiveBattleScreen extends StatefulWidget {
  const ImmersiveBattleScreen({
    super.key,
    required this.repository,
    required this.sync,
    required this.mine,
    required this.rival,
  });

  final CatRepository repository;
  final SyncService sync;
  final CollectedCat mine;
  final CollectedCat rival;

  @override
  State<ImmersiveBattleScreen> createState() => _ImmersiveBattleScreenState();
}

class _ImmersiveBattleScreenState extends State<ImmersiveBattleScreen>
    with WidgetsBindingObserver {
  AuthoritativeBattleState? _state;
  BattleSceneGame? _game;
  Timer? _clock;
  Timer? _poller;
  bool _busy = true;
  bool _reducedMotion = false;
  bool _lowPower = false;
  int _shownEvents = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _poller = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _poller?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _start() async {
    try {
      final state = await widget.sync.startBattle(
        mine: widget.mine,
        opponent: widget.rival,
      );
      if (!mounted) return;
      _installState(state, first: true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    final current = _state;
    if (current == null || current.finished || _busy) return;
    try {
      final next = await widget.sync.getBattle(
        matchId: current.matchId,
        cardId: widget.mine.id,
      );
      if (mounted && next.revision != current.revision) _installState(next);
    } on NakamaNetworkException {
      // Polling resumes automatically. Keep the reconnectable state visible.
    } on NakamaTimeoutException {
      // Same as above.
    }
  }

  void _installState(AuthoritativeBattleState state, {bool first = false}) {
    final priorCount = first ? state.events.length : _shownEvents;
    _game ??= _newGame();
    for (final event in state.events.skip(priorCount)) {
      _game!.playEvent(event, playerCardId: widget.mine.id);
    }
    if (state.finished) _game!.playFinish();
    _shownEvents = state.events.length;
    setState(() {
      _state = state;
      _error = null;
    });
  }

  Color _accentOf(CollectedCat cat) {
    final h = cat.accentColor.replaceFirst('#', '');
    return Color(int.tryParse('FF$h', radix: 16) ?? 0xFFFDBA74);
  }

  BattleSceneGame _newGame() => BattleSceneGame(
    arenaAsset: widget.mine.stars.isEven
        ? 'assets/art/battle/cafe_arena.jpg'
        : 'assets/art/battle/rooftop_arena.jpg',
    playerName: widget.mine.name,
    opponentName: widget.rival.name,
    playerImagePath: widget.mine.imagePath,
    opponentImagePath: widget.rival.imagePath,
    playerAccent: _accentOf(widget.mine),
    opponentAccent: _accentOf(widget.rival),
    reducedMotion: _reducedMotion,
    lowPower: _lowPower,
  );

  Future<void> _act(TacticalAction action) async {
    final state = _state;
    if (state == null || _busy) return;
    setState(() => _busy = true);
    try {
      final next = await widget.sync.submitBattleAction(
        matchId: state.matchId,
        expectedRevision: state.revision,
        action: action,
      );
      if (mounted) _installState(next);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'Action was not accepted: $error');
        await _refresh();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _replay() async {
    final state = _state;
    final game = _game;
    if (state == null || game == null) return;
    for (final event in state.events) {
      if (!mounted) return;
      game.playEvent(event, playerCardId: widget.mine.id);
      await Future<void>.delayed(
        Duration(milliseconds: _reducedMotion ? 180 : 650),
      );
    }
  }

  void _setMotion({bool? reduced, bool? lowPower}) {
    setState(() {
      _reducedMotion = reduced ?? _reducedMotion;
      _lowPower = lowPower ?? _lowPower;
      _game = _newGame();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      backgroundColor: const Color(0xff080510),
      body: SafeArea(
        child: state == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : _ErrorPanel(error: _error!, retry: _start),
              )
            : Column(
                children: [
                  _BattleTopBar(
                    state: state,
                    mine: widget.mine,
                    reducedMotion: _reducedMotion,
                    lowPower: _lowPower,
                    onReducedMotion: (value) => _setMotion(reduced: value),
                    onLowPower: (value) => _setMotion(lowPower: value),
                    onSurrender: state.finished
                        ? null
                        : () => _act(TacticalAction.surrender),
                  ),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        GameWidget(game: _game ??= _newGame()),
                        Positioned(
                          left: 12,
                          right: 12,
                          top: 10,
                          child: _FighterBars(
                            state: state,
                            mineId: widget.mine.id,
                          ),
                        ),
                        if (_error != null)
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 10,
                            child: Material(
                              color: Colors.red.shade900.withValues(alpha: .9),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Text(_error!),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _controls(state),
                ],
              ),
      ),
    );
  }

  Widget _controls(AuthoritativeBattleState state) {
    final mine = state.fighters.firstWhere(
      (fighter) => fighter.cardId == widget.mine.id,
    );
    final rival = state.fighters.firstWhere(
      (fighter) => fighter.cardId != widget.mine.id,
    );
    final myTurn = state.turnUserId == mine.userId;
    final seconds = state.turnDeadline
        .difference(DateTime.now().toUtc())
        .inSeconds
        .clamp(0, 30);
    return Container(
      color: const Color(0xff100b18),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  myTurn ? Icons.bolt : Icons.hourglass_bottom,
                  color: myTurn ? Colors.amber : Colors.white54,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    state.finished
                        ? state.winnerUserId == mine.userId
                              ? 'Victory'
                              : 'Defeat'
                        : myTurn
                        ? 'Your turn'
                        : '${rival.name} is choosing',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (!state.finished)
                  Text(
                    '${seconds}s',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (state.finished)
                  TextButton.icon(
                    onPressed: _replay,
                    icon: const Icon(Icons.replay),
                    label: const Text('Replay'),
                  ),
              ],
            ),
            if (!state.finished) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 88,
                child: BattleActionPanel(
                  actor: mine,
                  target: rival,
                  enabled: myTurn && !_busy,
                  onAction: _act,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BattleTopBar extends StatelessWidget {
  const _BattleTopBar({
    required this.state,
    required this.mine,
    required this.reducedMotion,
    required this.lowPower,
    required this.onReducedMotion,
    required this.onLowPower,
    required this.onSurrender,
  });

  final AuthoritativeBattleState state;
  final CollectedCat mine;
  final bool reducedMotion;
  final bool lowPower;
  final ValueChanged<bool> onReducedMotion;
  final ValueChanged<bool> onLowPower;
  final VoidCallback? onSurrender;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: Text(
            state.localDevelopmentOpponent ? 'Encounter' : 'Duel',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.tune),
          onSelected: (value) {
            if (value == 'motion') onReducedMotion(!reducedMotion);
            if (value == 'power') onLowPower(!lowPower);
            if (value == 'surrender') onSurrender?.call();
          },
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: 'motion',
              checked: reducedMotion,
              child: const Text('Reduced motion'),
            ),
            CheckedPopupMenuItem(
              value: 'power',
              checked: lowPower,
              child: const Text('Low-power effects'),
            ),
            PopupMenuItem(
              value: 'surrender',
              enabled: onSurrender != null,
              child: const Text('Surrender'),
            ),
          ],
        ),
      ],
    );
  }
}

class _FighterBars extends StatelessWidget {
  const _FighterBars({required this.state, required this.mineId});
  final AuthoritativeBattleState state;
  final String mineId;

  @override
  Widget build(BuildContext context) {
    final mine = state.fighters.firstWhere(
      (fighter) => fighter.cardId == mineId,
    );
    final rival = state.fighters.firstWhere(
      (fighter) => fighter.cardId != mineId,
    );
    return Row(
      children: [
        Expanded(child: _bar(mine, Alignment.centerLeft)),
        const SizedBox(width: 32),
        Expanded(child: _bar(rival, Alignment.centerRight)),
      ],
    );
  }

  Widget _bar(BattleCombatant fighter, Alignment alignment) => Column(
    crossAxisAlignment: alignment == Alignment.centerLeft
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.end,
    children: [
      Text(
        fighter.name,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          shadows: [Shadow(blurRadius: 5, color: Colors.black)],
        ),
      ),
      const SizedBox(height: 3),
      LinearProgressIndicator(
        value: fighter.hp / 100,
        minHeight: 10,
        color: fighter.hp > 30 ? Colors.greenAccent : Colors.redAccent,
        backgroundColor: Colors.black54,
      ),
    ],
  );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.retry});
  final String error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(error, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: retry, child: const Text('Try again')),
      ],
    ),
  );
}
