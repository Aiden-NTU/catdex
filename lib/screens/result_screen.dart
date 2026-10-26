import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../data/cat_repository.dart';
import '../game/star_rank.dart';
import '../ml/image_utils.dart';
import '../models/cat.dart';
import '../models/scan_result.dart';
import '../services/location_service.dart';
import '../services/nakama_client.dart';
import '../services/sync_service.dart';
import '../widgets/cat_card_frame.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.repository,
    required this.outcome,
    this.debugBypassGeo = false,
  });

  final CatRepository repository;
  final ScanOutcome outcome;
  final bool debugBypassGeo;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with SingleTickerProviderStateMixin {
  static const _developmentMode = bool.fromEnvironment(
    'CATDEX_DEVELOPMENT_MODE',
  );
  late final TextEditingController _nameController;
  final String _requestId = const Uuid().v4();
  bool _saving = false;
  bool _forceEnroll = false;
  LocationFix? _fix;
  String? _geoError;
  String? _queueMessage;
  late final AnimationController _starAnim;

  @override
  void initState() {
    super.initState();
    final breed = widget.outcome.breed.info.displayName;
    _nameController = TextEditingController(text: breed);
    _starAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _loadGeo();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!animationsEnabled(context)) _starAnim.value = 1;
  }

  Future<void> _loadGeo() async {
    try {
      final fix = await LocationService.developmentAware().current();
      if (!mounted) return;
      final cooled = await widget.repository.isCellOnCooldown(fix.cellId);
      setState(() {
        _fix = fix;
        if (cooled && !_canBypassGeo && !_serverConfigured) {
          _geoError = 'Cell on cooldown — walk to another block (~15 min).';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _geoError = '$e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _starAnim.dispose();
    super.dispose();
  }

  MatchDecision get _decision {
    if (_forceEnroll && _developmentFeatures) return MatchDecision.unique;
    return widget.outcome.match.decision;
  }

  bool get _developmentFeatures => _developmentMode && !kReleaseMode;

  bool get _canBypassGeo => _developmentFeatures && widget.debugBypassGeo;

  bool get _serverConfigured =>
      SyncService(widget.repository).config.serverKey.isNotEmpty;

  StarRoll get _previewRoll {
    final cell = _fix?.cellId ?? 'unknown';
    return StarRank.fromBreed(
      info: widget.outcome.breed.info,
      embedding: widget.outcome.embedding,
      h3Cell: cell,
    );
  }

  Future<void> _enroll() async {
    if (_geoError != null && !_canBypassGeo) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_geoError!)));
      return;
    }
    setState(() => _saving = true);
    try {
      final fix = _fix ?? await LocationService.developmentAware().current();
      if (!_serverConfigured &&
          await widget.repository.isCellOnCooldown(fix.cellId) &&
          !_canBypassGeo) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This block needs a rest. Walk on.')),
          );
        }
        return;
      }
      final info = widget.outcome.breed.info;
      final roll = StarRank.fromBreed(
        info: info,
        embedding: widget.outcome.embedding,
        h3Cell: fix.cellId,
      );
      Map<String, dynamic>? authoritative;
      if (_serverConfigured) {
        try {
          final result = await SyncService(widget.repository).enroll(
            requestId: _requestId,
            fingerprint: base64Encode(
              widget.outcome.embedding.buffer.asUint8List(),
            ),
            name: _nameController.text.trim(),
            breed: info.displayName,
            breedConfidence: widget.outcome.breed.confidence,
            h3Cell: fix.cellId,
            lat: fix.lat,
            lng: fix.lng,
            accuracyM: fix.accuracyM,
            capturedAt: fix.capturedAt,
            baseAttack: info.attack,
            baseDefense: info.defense,
            baseSpeed: info.speed,
            ability: info.ability,
            accentColor: info.accent,
          );
          authoritative = result.card.json;
        } on NakamaQueuedException {
          if (mounted) {
            setState(() {
              _queueMessage =
                  'Offline: enrollment queued. Keep this screen until sync '
                  'returns the authoritative card.';
            });
          }
          return;
        }
      }
      final id = authoritative?['id'] as String? ?? const Uuid().v4();
      final jpeg = ImageUtils.encodeJpeg(widget.outcome.crop);
      final path = await widget.repository.saveCropImage(id, jpeg);
      final serverStats = authoritative?['stats'] as Map?;
      final cat = CollectedCat(
        id: id,
        name: _nameController.text.trim().isEmpty
            ? (authoritative?['name'] as String? ?? info.displayName)
            : (authoritative?['name'] as String? ??
                  _nameController.text.trim()),
        breed: authoritative?['breed'] as String? ?? info.displayName,
        breedConfidence:
            (authoritative?['breedConfidence'] as num?)?.toDouble() ??
            widget.outcome.breed.confidence,
        embedding: widget.outcome.embedding,
        createdAt:
            DateTime.tryParse(authoritative?['createdAt'] as String? ?? '') ??
            DateTime.now(),
        statsJson: jsonEncode(serverStats ?? roll.toStatsJson(info)),
        imagePath: path,
        accentColor: authoritative?['accentColor'] as String? ?? info.accent,
        stars: (authoritative?['stars'] as num?)?.toInt() ?? roll.stars,
        h3Cell: authoritative?['h3Cell'] as String? ?? fix.cellId,
        lat: (authoritative?['lat'] as num?)?.toDouble() ?? fix.lat,
        lng: (authoritative?['lng'] as num?)?.toDouble() ?? fix.lng,
      );
      await widget.repository.insert(cat);
      await widget.repository.markCellCooldown(fix.cellId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final breed = widget.outcome.breed;
    final match = widget.outcome.match;
    final decision = _decision;
    final rgb = img.copyResize(widget.outcome.crop, width: 320);
    final bytes = ImageUtils.encodeJpeg(rgb);
    final roll = _previewRoll;

    String statusTitle;
    String statusBody;
    Color statusColor;
    switch (decision) {
      case MatchDecision.duplicate:
        statusTitle = 'Already collected';
        statusBody =
            'Looks like ${match.matchedCat?.name ?? 'a cat you own'} '
            '(${(match.bestSimilarity * 100).toStringAsFixed(0)}% match).';
        statusColor = const Color(0xFFEF4444);
      case MatchDecision.ambiguous:
        statusTitle = 'Not sure…';
        statusBody =
            'Similar to ${match.matchedCat?.name ?? 'an owned cat'} '
            '(${(match.bestSimilarity * 100).toStringAsFixed(0)}%). '
            'Try another angle, or enroll anyway.';
        statusColor = const Color(0xFFF59E0B);
      case MatchDecision.unique:
        statusTitle = 'New cat card!';
        statusBody = 'Star rank rolled for this cell.';
        statusColor = const Color(0xFF22C55E);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0C0A09),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Cat card'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AspectRatio(
                aspectRatio: .75,
                child: ScaleTransition(
                  scale: CurvedAnimation(
                    parent: _starAnim,
                    curve: Curves.easeOutBack,
                  ),
                  child: Semantics(
                    image: true,
                    label:
                        'New ${breed.info.displayName} card, ${roll.stars} of 5 stars, battle power ${roll.battlePower}',
                    child: CatCardFrame(
                      image: Image.memory(
                        bytes,
                        fit: BoxFit.cover,
                        semanticLabel: 'Scanned cat photo',
                      ),
                      footer: ExcludeSemantics(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                breed.info.displayName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${'★' * roll.stars}${'☆' * (5 - roll.stars)}'
                                '  ·  PWR ${roll.battlePower}',
                                style: const TextStyle(
                                  color: Color(0xFFFDE68A),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ScaleTransition(
            scale: CurvedAnimation(parent: _starAnim, curve: Curves.elasticOut),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF78350F), Color(0xFF1C1917)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFBBF24)),
              ),
              child: Column(
                children: [
                  Text(
                    '★' * roll.stars + '☆' * (5 - roll.stars),
                    style: const TextStyle(
                      color: Color(0xFFFBBF24),
                      fontSize: 28,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${roll.stars}-STAR  ·  ×${roll.multiplier.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Color(0xFFFDE68A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ATK ${roll.finalAttack}  DEF ${roll.finalDefense}  '
                    'SPD ${roll.finalSpeed}  ·  PWR ${roll.battlePower}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor.withValues(alpha: 0.5)),
            ),
            child: Semantics(
              liveRegion: true,
              container: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    switch (decision) {
                      MatchDecision.duplicate => Icons.content_copy_rounded,
                      MatchDecision.ambiguous => Icons.help_outline_rounded,
                      MatchDecision.unique => Icons.auto_awesome_rounded,
                    },
                    color: statusColor,
                    semanticLabel: switch (decision) {
                      MatchDecision.duplicate => 'Duplicate',
                      MatchDecision.ambiguous => 'Uncertain',
                      MatchDecision.unique => 'New',
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusTitle,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          statusBody,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_fix != null) ...[
            const SizedBox(height: 8),
            Text(
              'Cell ${_fix!.cellId}  ·  '
              '${_fix!.lat.toStringAsFixed(4)}, ${_fix!.lng.toStringAsFixed(4)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          if (_geoError != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_off_rounded,
                    color: Color(0xFFFCA5A5),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _geoError!,
                      style: const TextStyle(color: Color(0xFFFCA5A5)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_queueMessage != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.schedule_send_rounded, color: Color(0xFFFDE68A)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _queueMessage!,
                      style: const TextStyle(color: Color(0xFFFDE68A)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            breed.info.displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '${breed.info.ability} — ${breed.info.abilityDesc}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 20),
          if (decision != MatchDecision.duplicate) ...[
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_saving) _enroll();
              },
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Give it a name',
                labelStyle: const TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFFDBA74)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _enroll,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFDBA74),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _saving
                  ? Semantics(
                      label: 'Saving card',
                      liveRegion: true,
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Text('Save card to Catdex'),
            ),
          ],
          if (decision == MatchDecision.ambiguous && _developmentFeatures)
            TextButton(
              onPressed: () => setState(() => _forceEnroll = true),
              child: const Text('Save as a new cat'),
            ),
          if (decision == MatchDecision.duplicate)
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Try again'),
            ),
        ],
      ),
    );
  }
}
