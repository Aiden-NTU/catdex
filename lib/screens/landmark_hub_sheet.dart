import 'package:flutter/material.dart';

import '../data/cat_repository.dart';
import '../game/world_spawns.dart';
import '../services/sync_service.dart';
import 'deck_pick_sheet.dart';

Future<void> showLandmarkHubSheet(
  BuildContext context, {
  required LandmarkHub hub,
  required CatRepository repository,
  required SyncService sync,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => LandmarkHubSheet(
      hub: hub,
      repository: repository,
      sync: sync,
    ),
  );
}

class LandmarkHubSheet extends StatelessWidget {
  const LandmarkHubSheet({
    super.key,
    required this.hub,
    required this.repository,
    required this.sync,
  });

  final LandmarkHub hub;
  final CatRepository repository;
  final SyncService sync;

  @override
  Widget build(BuildContext context) {
    final ends = hub.endsAt.toLocal();
    final timeLeft = hub.endsAt.difference(DateTime.now().toUtc());
    final minutes = timeLeft.inMinutes.clamp(0, 999);
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1917),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(
                Icons.place,
                color: Color(0xFFFDBA74),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hub.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hub.subtitle,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: hub.progressRatio.clamp(0, 1),
              minHeight: 10,
              backgroundColor: Colors.white12,
              color: const Color(0xFFFDBA74),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${hub.progress}/${hub.goal} community progress · ${minutes}m left'
            ' (until ${ends.hour.toString().padLeft(2, '0')}:'
            '${ends.minute.toString().padLeft(2, '0')})',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await showDeckPickAndDuel(
                context,
                repository: repository,
                sync: sync,
                rivalName: '${hub.title} Champion',
                npcEncounterId: 'enc-hub-${hub.id}',
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFDBA74),
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text(
              'Challenge the hub champion',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to map'),
          ),
        ],
      ),
    );
  }
}
