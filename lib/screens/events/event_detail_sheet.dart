import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/location_service.dart';
import '../../services/nakama_client.dart';

class EventContribution {
  const EventContribution({
    required this.amount,
    required this.type,
    this.squadId = '',
    this.checkpointId = '',
    this.stationary = false,
  });

  final int amount;
  final String type;
  final String squadId;
  final String checkpointId;
  final bool stationary;
}

class EventDetailSheet extends StatefulWidget {
  const EventDetailSheet({
    super.key,
    required this.event,
    required this.fix,
    required this.onContribute,
    required this.onSummary,
  });

  final NakamaEvent event;
  final LocationFix fix;
  final Future<NakamaContributionResult> Function(EventContribution value)
  onContribute;
  final Future<Map<String, dynamic>> Function() onSummary;

  @override
  State<EventDetailSheet> createState() => _EventDetailSheetState();
}

class _EventDetailSheetState extends State<EventDetailSheet> {
  late final Timer _timer;
  bool _submitting = false;
  String? _message;
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (widget.event.state == 'ended') {
      widget
          .onSummary()
          .then((value) {
            if (mounted) setState(() => _summary = value);
          })
          .catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _submit(EventContribution value) async {
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      final result = await widget.onContribute(value);
      if (!mounted) return;
      setState(() {
        _message =
            'Added ${result.accepted} · +${result.personalReward + result.communityReward} Paw Coins';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final remaining = event.endsAt.difference(DateTime.now());
    final ended = remaining.isNegative || event.state == 'ended';
    final scheduled = event.state == 'scheduled';
    final summary = _summary;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              event.title,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              event.description,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  ended ? Icons.flag_circle : Icons.timer_outlined,
                  color: const Color(0xFFFDBA74),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ended
                        ? 'Event ended'
                        : scheduled
                        ? 'Starts in ${_duration(event.startsAt.difference(DateTime.now()), suffix: '')}'
                        : _duration(remaining),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text('${event.progress} / ${event.goal}'),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: event.goal == 0 ? 0 : event.progress / event.goal,
              minHeight: 9,
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFFFDBA74),
            ),
            const SizedBox(height: 8),
            Text(
              'You have helped ${event.myContribution} of ${event.perUserCap} times.',
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
            const SizedBox(height: 18),
            if (!ended && !scheduled) _actionFor(event),
            if (ended && summary != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  '${summary['completed'] == true ? 'Goal reached!' : 'Event complete'} '
                  '${summary['contributors'] ?? 0} contributors · '
                  'You added ${summary['myContribution'] ?? 0} · '
                  '+${((summary['personalReward'] as num?)?.toInt() ?? 0) + ((summary['communityReward'] as num?)?.toInt() ?? 0)} Paw Coins',
                  style: const TextStyle(
                    color: Color(0xFFFDBA74),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (_submitting)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (_message case final message?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  message,
                  style: const TextStyle(color: Color(0xFFFDBA74)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _actionFor(NakamaEvent event) {
    switch (event.kind) {
      case 'cat_cafe_rally':
        return FilledButton.icon(
          onPressed: _submitting
              ? null
              : () => _submit(const EventContribution(amount: 1, type: 'feed')),
          icon: const Icon(Icons.restaurant),
          label: const Text('Drop a treat'),
        );
      case 'cardboard_fortress':
        return FilledButton.icon(
          onPressed: _submitting
              ? null
              : () => _submit(
                  const EventContribution(
                    amount: 2,
                    type: 'squad',
                    squadId: 'neighborhood',
                  ),
                ),
          icon: const Icon(Icons.groups),
          label: const Text('Send your cats'),
        );
      case 'laser_pointer_chase':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: _submitting
                  ? null
                  : () => _submit(
                      const EventContribution(
                        amount: 1,
                        type: 'checkpoint',
                        checkpointId: 'loop-a',
                      ),
                    ),
              icon: const Icon(Icons.directions_walk),
              label: const Text('Chase the dot'),
            ),
            TextButton.icon(
              onPressed: _submitting
                  ? null
                  : () => _submit(
                      const EventContribution(
                        amount: 1,
                        type: 'checkpoint',
                        checkpointId: 'accessible',
                        stationary: true,
                      ),
                    ),
              icon: const Icon(Icons.accessible),
              label: const Text('Play from here'),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

String _duration(Duration value, {String suffix = ' remaining'}) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  final seconds = value.inSeconds.remainder(60);
  return '${hours > 0 ? '${hours}h ' : ''}'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}$suffix';
}

String _friendlyError(Object error) {
  final text = '$error';
  if (text.contains('outside event area')) {
    return 'Move closer to this event, then refresh your location.';
  }
  if (text.contains('queued')) {
    return 'Offline: contribution queued for retry.';
  }
  return 'Could not contribute. Check your resources and try again.';
}
