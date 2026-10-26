import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../config/client_quality_config.dart';
import '../../config/client_settings.dart';
import '../../services/playable_location.dart';

class ClientSettingsScreen extends StatelessWidget {
  const ClientSettingsScreen({
    super.key,
    required this.settings,
    this.location,
    this.onLocationChanged,
  });

  final ClientSettings settings;
  final PlayableLocationProvider? location;
  final VoidCallback? onLocationChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          settings,
          ?location,
        ]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Settings',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1C1917),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: settings.lowPower,
              onChanged: settings.setLowPower,
              secondary: const Icon(Icons.battery_saver),
              title: const Text('Low-power mode'),
              subtitle: const Text(
                'Reduces scan frequency, map refreshes, and battle polling.',
              ),
            ),
            SwitchListTile(
              value: settings.reducedMotion,
              onChanged: settings.setReducedMotion,
              secondary: const Icon(Icons.motion_photos_off),
              title: const Text('Reduced motion'),
              subtitle: const Text(
                'Minimizes non-essential movement and battle effects.',
              ),
            ),
            if (!kReleaseMode && location != null) ...[
              const Divider(height: 32),
              const Text(
                'Developer',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF78716C),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.pin_drop),
                title: const Text('Set map pin'),
                subtitle: Text(
                  location!.fix == null
                      ? 'No position yet'
                      : '${location!.fix!.lat.toStringAsFixed(5)}, '
                          '${location!.fix!.lng.toStringAsFixed(5)}'
                          ' · ${location!.source.name}',
                ),
                onTap: () => _promptPin(context),
              ),
              ListTile(
                leading: const Icon(Icons.my_location),
                title: const Text('Clear pin / retry GPS'),
                onTap: () async {
                  await location!.clearManualAndRetryDevice();
                  onLocationChanged?.call();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
            if (ClientQualityConfig.simulatorEnabled)
              const ListTile(
                leading: Icon(Icons.developer_mode),
                title: Text('Desktop simulator active'),
                subtitle: Text(
                  'Fixture scans are enabled for this non-release build.',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptPin(BuildContext context) async {
    final loc = location;
    if (loc == null) return;
    final latCtrl = TextEditingController(
      text: loc.fix?.lat.toStringAsFixed(5) ?? '51.50740',
    );
    final lngCtrl = TextEditingController(
      text: loc.fix?.lng.toStringAsFixed(5) ?? '-0.12780',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Map pin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: latCtrl,
              decoration: const InputDecoration(labelText: 'Latitude'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
            ),
            TextField(
              controller: lngCtrl,
              decoration: const InputDecoration(labelText: 'Longitude'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pin'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final lat = double.tryParse(latCtrl.text.trim());
    final lng = double.tryParse(lngCtrl.text.trim());
    if (lat == null || lng == null) return;
    await loc.setManual(lat, lng);
    onLocationChanged?.call();
    if (context.mounted) Navigator.pop(context);
  }
}
