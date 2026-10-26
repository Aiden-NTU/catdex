import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/cat_repository.dart';
import '../../models/cat.dart';
import '../../services/nakama_client.dart';
import '../../services/sync_service.dart';
import '../../widgets/care/care_meter.dart';

class CareRoomScreen extends StatefulWidget {
  const CareRoomScreen({
    super.key,
    required this.repository,
    required this.catId,
    this.sync,
  });

  final CatRepository repository;
  final String catId;
  final SyncService? sync;

  @override
  State<CareRoomScreen> createState() => _CareRoomScreenState();
}

class _CareRoomScreenState extends State<CareRoomScreen> {
  late final SyncService _sync = widget.sync ?? SyncService(widget.repository);
  CollectedCat? _cat;
  NakamaCareAccount? _account;
  bool _loading = true;
  String? _pending;
  String? _error;
  bool _celebrate = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cachedCat = await widget.repository.getById(widget.catId);
      final cachedAccount = await widget.repository.getAccountCache();
      if (mounted) {
        setState(() {
          _cat = cachedCat;
          _account = NakamaCareAccount({
            'pawCoins': cachedAccount.pawCoins,
            'dailyEarned': cachedAccount.dailyEarned,
            'dailyCap': cachedAccount.dailyCap,
            'treats': cachedAccount.treats,
            'groomingSupplies': cachedAccount.groomingSupplies,
          });
        });
      }
      final state = await _sync.getCareState(widget.catId);
      await _refreshFromState(state);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshFromState(NakamaCareState state) async {
    final cat = await widget.repository.getById(widget.catId);
    if (!mounted) return;
    setState(() {
      _cat = cat;
      _account = state.account;
    });
  }

  Future<void> _act(String action) async {
    if (_pending != null) return;
    setState(() {
      _pending = action;
      _error = null;
      _celebrate = true;
    });
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 260), () {
        if (mounted) setState(() => _celebrate = false);
      }),
    );
    try {
      final state = await _sync.careAction(
        cardId: widget.catId,
        action: action,
      );
      await _refreshFromState(state);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_label(action)} complete · +${state.xpAwarded} XP'
            '${state.coinsAwarded > 0 ? ' · +${state.coinsAwarded} 🐾' : ''}',
          ),
        ),
      );
    } on NakamaQueuedException {
      if (mounted) {
        setState(() => _error = 'Saved offline. It will reconcile on sync.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  String _friendlyError(Object error) {
    if (error is NakamaException) return error.message;
    return 'Care action failed. Please try again.';
  }

  static String _label(String action) =>
      '${action[0].toUpperCase()}${action.substring(1)}';

  @override
  Widget build(BuildContext context) {
    final cat = _cat;
    if (_loading && cat == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (cat == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Care room')),
        body: Center(
          child: FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: Text(_error ?? 'Try again'),
          ),
        ),
      );
    }
    final account = _account;
    return Scaffold(
      backgroundColor: const Color(0xFF171026),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('${cat.name}’s room'),
        actions: [
          if (account != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '🐾 ${account.pawCoins}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 32),
          children: [
            _RoomScene(cat: cat, celebrate: _celebrate),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Level ${cat.level}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text('${cat.xp} XP'),
              ],
            ),
            const SizedBox(height: 7),
            LinearProgressIndicator(
              value: cat.levelProgress,
              minHeight: 7,
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFFFFB86C),
              backgroundColor: Colors.white12,
            ),
            const SizedBox(height: 18),
            Card(
              color: Colors.white.withValues(alpha: .07),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    CareMeter(
                      icon: Icons.bolt,
                      label: 'Energy',
                      value: cat.energy,
                      color: const Color(0xFFFDE047),
                    ),
                    const SizedBox(height: 14),
                    CareMeter(
                      icon: Icons.restaurant,
                      label: 'Full tummy',
                      value: cat.hunger,
                      color: const Color(0xFFFB923C),
                    ),
                    const SizedBox(height: 14),
                    CareMeter(
                      icon: Icons.sentiment_very_satisfied,
                      label: 'Mood',
                      value: cat.mood,
                      color: const Color(0xFFF472B6),
                    ),
                    const SizedBox(height: 14),
                    CareMeter(
                      icon: Icons.favorite,
                      label: 'Bond',
                      value: cat.bond,
                      color: const Color(0xFFFB7185),
                    ),
                    const SizedBox(height: 14),
                    CareMeter(
                      icon: Icons.auto_awesome,
                      label: 'Ability mastery',
                      value: cat.abilityMastery,
                      color: const Color(0xFFA78BFA),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              MaterialBanner(
                content: Text(_error!),
                leading: const Icon(Icons.info_outline),
                actions: [
                  TextButton(onPressed: _load, child: const Text('Refresh')),
                ],
              ),
            ],
            const SizedBox(height: 14),
            if (account != null)
              Text(
                '🎁 ${account.treats} treats  ·  🧴 ${account.groomingSupplies} grooming supplies'
                '  ·  ${account.dailyEarned}/${account.dailyCap} daily coins',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.25,
              children: [
                _ActionButton('feed', '🍗', _pending, _act),
                _ActionButton('play', '🧶', _pending, _act),
                _ActionButton('groom', '🪮', _pending, _act),
                _ActionButton('train', '✨', _pending, _act),
                _ActionButton('rest', '🌙', _pending, _act),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Come back whenever you like—there are no neglect penalties.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomScene extends StatelessWidget {
  const _RoomScene({required this.cat, required this.celebrate});

  final CollectedCat cat;
  final bool celebrate;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF45366B), Color(0xFF2B2041)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned(
            top: 22,
            right: 28,
            child: Text('✨', style: TextStyle(fontSize: 28)),
          ),
          const Positioned(
            bottom: 20,
            left: 24,
            child: Text('🧺', style: TextStyle(fontSize: 52)),
          ),
          AnimatedScale(
            scale: celebrate ? 1.12 : 1,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: Hero(
              tag: 'care-${cat.id}',
              child: ClipOval(
                child: SizedBox(
                  width: 170,
                  height: 170,
                  child:
                      cat.imagePath != null && File(cat.imagePath!).existsSync()
                      ? Image.file(File(cat.imagePath!), fit: BoxFit.cover)
                      : const ColoredBox(
                          color: Color(0xFF6D5A8C),
                          child: Icon(Icons.pets, size: 74),
                        ),
                ),
              ),
            ),
          ),
          if (celebrate)
            const Positioned(
              top: 34,
              child: Text('♡  ✨  ♡', style: TextStyle(fontSize: 30)),
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(this.action, this.emoji, this.pending, this.onTap);

  final String action;
  final String emoji;
  final String? pending;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final active = pending == action;
    return FilledButton.tonal(
      onPressed: pending == null ? () => onTap(action) : null,
      child: active
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text('$emoji  ${_CareRoomScreenState._label(action)}'),
    );
  }
}
