import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;
import 'package:spine_flutter/spine_flutter.dart' show initSpineFlutter;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'config/client_settings.dart';
import 'config/nakama_config.dart';
import 'data/cat_repository.dart';
import 'ml/fixture_scan_pipeline.dart';
import 'ml/scan_pipeline.dart';
import 'screens/cat_den_sheet.dart';
import 'screens/hatch_reveal_screen.dart';
import 'screens/map_screen.dart';
import 'screens/scan_screen.dart';
import 'services/lifecycle/sensor_work_tracker.dart';
import 'services/location_service.dart';
import 'services/playable_location.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Industry 2D character runtimes (Spine skeletal + Rive state machines).
  await initSpineFlutter(enableMemoryDebugging: false);
  await rive.RiveNative.init();

  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final repository = await CatRepository.open();
  final desktop = !kIsWeb &&
      (Platform.isLinux || Platform.isWindows || Platform.isMacOS);
  // Talk to real local Nakama (docker-compose defaults). Do not force
  // developmentMode — that silently faked battles and inventory.
  final sync = SyncService(
    repository,
    config: NakamaConfig.fromEnvironment(),
  );
  final settings = await ClientSettings.load();
  final workTracker = SensorWorkTracker();
  final location = PlayableLocationProvider(
    device: LocationService(tracker: workTracker),
    tracker: workTracker,
  );
  await location.bootstrap();

  ScannerEngine? pipeline;
  Object? pipelineError;
  try {
    pipeline = desktop && !kReleaseMode
        ? await FixtureScanPipeline.create(repository)
        : await ScanPipeline.create(repository);
  } catch (e, st) {
    pipelineError = e;
    debugPrint('Pipeline load failed: $e\n$st');
  }

  runApp(
    CatdexApp(
      repository: repository,
      sync: sync,
      pipeline: pipeline,
      pipelineError: pipelineError,
      settings: settings,
      location: location,
      workTracker: workTracker,
    ),
  );
}

class CatdexApp extends StatefulWidget {
  const CatdexApp({
    super.key,
    required this.repository,
    required this.sync,
    required this.pipeline,
    required this.settings,
    required this.location,
    required this.workTracker,
    this.pipelineError,
  });

  final CatRepository repository;
  final SyncService sync;
  final ScannerEngine? pipeline;
  final Object? pipelineError;
  final ClientSettings settings;
  final PlayableLocationProvider location;
  final SensorWorkTracker workTracker;

  @override
  State<CatdexApp> createState() => _CatdexAppState();
}

class _CatdexAppState extends State<CatdexApp> {
  @override
  void dispose() {
    widget.pipeline?.close();
    widget.settings.dispose();
    widget.workTracker.dispose();
    widget.location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) => MaterialApp(
        title: 'Catdex',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFEA580C),
            brightness: Brightness.light,
          ),
          pageTransitionsTheme: widget.settings.reducedMotion
              ? const PageTransitionsTheme(
                  builders: {
                    TargetPlatform.android: _NoMotionTransitions(),
                    TargetPlatform.iOS: _NoMotionTransitions(),
                    TargetPlatform.linux: _NoMotionTransitions(),
                    TargetPlatform.macOS: _NoMotionTransitions(),
                    TargetPlatform.windows: _NoMotionTransitions(),
                  },
                )
              : null,
        ),
        home: HomeShell(
          repository: widget.repository,
          sync: widget.sync,
          pipeline: widget.pipeline,
          pipelineError: widget.pipelineError,
          settings: widget.settings,
          location: widget.location,
          workTracker: widget.workTracker,
        ),
      ),
    );
  }
}

class _NoMotionTransitions extends PageTransitionsBuilder {
  const _NoMotionTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.repository,
    required this.sync,
    required this.pipeline,
    required this.settings,
    required this.location,
    required this.workTracker,
    this.pipelineError,
  });

  final CatRepository repository;
  final SyncService sync;
  final ScannerEngine? pipeline;
  final Object? pipelineError;
  final ClientSettings settings;
  final PlayableLocationProvider location;
  final SensorWorkTracker workTracker;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  bool _foreground = true;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground != foreground) setState(() => _foreground = foreground);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _onCatchFinished({required bool enrolled}) async {
    if (!mounted) return;
    setState(() => _scanning = false);
    if (!enrolled) return;
    final cats = await widget.repository.getAll();
    if (!mounted || cats.isEmpty) return;
    final newest = cats.first;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, _, _) => HatchRevealScreen(
          cat: newest,
          onDone: () => Navigator.of(context).pop(),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    if (!mounted) return;
    await showCatDenSheet(context, repository: widget.repository);
  }

  @override
  Widget build(BuildContext context) {
    final pipeline = widget.pipeline;
    if (_scanning) {
      return Scaffold(
        backgroundColor: const Color(0xFF0C0A09),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: const Text('Catch'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => _onCatchFinished(enrolled: false),
          ),
        ),
        body: pipeline == null
            ? _PipelineError(error: widget.pipelineError)
            : ScanScreen(
                repository: widget.repository,
                pipeline: pipeline,
                active: _foreground,
                settings: widget.settings,
                workTracker: widget.workTracker,
                debugBypassGeo: !kReleaseMode,
                onEnrolled: () => _onCatchFinished(enrolled: true),
              ),
      );
    }
    return Scaffold(
      body: MapScreen(
        sync: widget.sync,
        repository: widget.repository,
        active: _foreground,
        location: widget.location,
        settings: widget.settings,
        workTracker: widget.workTracker,
        onCatch: () => setState(() => _scanning = true),
      ),
    );
  }
}

class _PipelineError extends StatelessWidget {
  const _PipelineError({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Could not load on-device models.\n\n$error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}
