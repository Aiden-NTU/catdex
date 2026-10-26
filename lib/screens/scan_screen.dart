import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../config/client_quality_config.dart';
import '../config/client_settings.dart';
import '../data/cat_repository.dart';
import '../ml/image_utils.dart';
import '../ml/scan_pipeline.dart';
import '../models/scan_result.dart';
import '../services/lifecycle/sensor_work_tracker.dart';
import '../widgets/gate_hint_banner.dart';
import 'result_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    required this.repository,
    required this.pipeline,
    required this.active,
    required this.settings,
    required this.workTracker,
    this.debugBypassGeo = false,
    this.onEnrolled,
  });

  final CatRepository repository;
  final ScannerEngine pipeline;
  final bool active;
  final ClientSettings settings;
  final SensorWorkTracker workTracker;
  final bool debugBypassGeo;
  final VoidCallback? onEnrolled;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _initializing = true;
  String? _error;
  String _hint = 'Point at a cat';
  bool _ready = false;
  DetectionBox? _box;
  bool _scanning = false;
  bool _frameBusy = false;
  int _frameSkip = 0;
  int _cameraGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _initCamera();
  }

  @override
  void didUpdateWidget(covariant ScanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    if (widget.active && WidgetsBinding.instance.lifecycleState ==
        AppLifecycleState.resumed) {
      _initCamera();
    } else {
      _stopCamera();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _stopCamera();
    } else if (widget.active) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (!widget.active || _controller != null) return;
    if (ClientQualityConfig.simulatorEnabled) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = 'Simulator active — use Demo cat or Pick photo.';
        });
      }
      return;
    }
    final generation = ++_cameraGeneration;
    setState(() {
      _initializing = true;
      _error = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _initializing = false;
          _error = 'No camera found — use Pick photo instead.';
        });
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted || !widget.active || generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }
      await controller.startImageStream(_onFrame);
      if (!mounted || !widget.active || generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }
      widget.workTracker.cameraStarted();
      if (mounted && widget.active) setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (e) {
      debugPrint('camera init: $e');
      setState(() {
        _initializing = false;
        _error = 'Camera unavailable — use Pick photo.';
      });
    }
  }

  void _onFrame(CameraImage image) {
    _frameSkip++;
    if (_frameSkip % widget.settings.previewFrameInterval != 0) return;
    if (_frameBusy || _scanning || !widget.active) return;
    final controller = _controller;
    if (controller == null) return;
    _frameBusy = true;
    widget.workTracker.inferenceRan();

    Future(() {
      final frame = ImageUtils.convertCameraImage(
        image,
        sensorOrientation: controller.description.sensorOrientation,
      );
      if (frame == null) return null;
      // Downscale for live preview speed
      final small = img.copyResize(
        frame,
        width: 320,
        interpolation: img.Interpolation.average,
      );
      return widget.pipeline.preview(small);
    }).then((tick) {
      if (!mounted || !widget.active || tick == null) return;
      setState(() {
        _hint = tick.quality.hint;
        _ready = tick.quality.passed;
        _box = tick.box;
      });
    }).whenComplete(() => _frameBusy = false);
  }

  Future<void> _scanFromCamera() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      await _pickPhoto();
      return;
    }
    setState(() => _scanning = true);
    try {
      await controller.stopImageStream();
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      final decoded = ImageUtils.decodeBytes(bytes);
      if (decoded == null) {
        _showSnack('Could not read photo');
        return;
      }
      await _runCapture(decoded);
    } catch (e) {
      debugPrint('scan: $e');
      _showSnack('Scan failed');
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
        try {
          if (widget.active) await _controller?.startImageStream(_onFrame);
        } catch (_) {}
      }
    }
  }

  Future<void> _pickPhoto() async {
    setState(() => _scanning = true);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final decoded = ImageUtils.decodeBytes(bytes);
      if (decoded == null) {
        _showSnack('Could not read photo');
        return;
      }
      widget.pipeline.resetGate();
      await _runCapture(decoded);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _scanDemoAsset() async {
    setState(() => _scanning = true);
    try {
      final data = await rootBundle.load('assets/demo/cat.jpg');
      final decoded = ImageUtils.decodeBytes(data.buffer.asUint8List());
      if (decoded == null) {
        _showSnack('Could not read demo cat');
        return;
      }
      widget.pipeline.resetGate();
      await _runCapture(decoded);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _runCapture(img.Image frame) async {
    final outcome = await widget.pipeline.capture(frame);
    if (!mounted) return;
    if (outcome == null) {
      _showSnack(_hint.isNotEmpty ? _hint : 'No cat found — try again');
      return;
    }
    final enrolled = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          repository: widget.repository,
          outcome: outcome,
          debugBypassGeo: widget.debugBypassGeo,
        ),
      ),
    );
    widget.pipeline.resetGate();
    if (enrolled == true && mounted) {
      final onEnrolled = widget.onEnrolled;
      if (onEnrolled != null) {
        onEnrolled();
      } else {
        _showSnack('Added to Catdex!');
      }
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera();
    super.dispose();
  }

  void _stopCamera() {
    _cameraGeneration++;
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    widget.workTracker.cameraStopped();
    unawaited(controller.dispose());
    if (mounted) {
      setState(() {
        _initializing = false;
        _frameBusy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_controller != null && _controller!.value.isInitialized)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller!.value.previewSize?.height ?? 1,
              height: _controller!.value.previewSize?.width ?? 1,
              child: CameraPreview(_controller!),
            ),
          )
        else
          Container(
            color: const Color(0xFF1C1917),
            child: Center(
              child: _initializing
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error ?? 'Starting camera…',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
            ),
          ),
        if (_box != null)
          CustomPaint(
            painter: _BoxPainter(box: _box!, ready: _ready),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                GateHintBanner(hint: _hint, ready: _ready),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton.icon(
                      onPressed: _scanning ? null : _pickPhoto,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Photo'),
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                    ),
                    Semantics(
                      button: true,
                      label: 'Capture cat scan',
                      hint: _ready
                          ? 'Cat is ready to capture'
                          : 'Center a clear cat before capturing',
                      enabled: !_scanning,
                      child: GestureDetector(
                        onTap: _scanning ? null : _scanFromCamera,
                        child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _ready
                                ? const Color(0xFF86EFAC)
                                : Colors.white70,
                            width: 4,
                          ),
                          color: _scanning
                              ? Colors.white24
                              : const Color(0xFFFDBA74),
                        ),
                        child: _scanning
                            ? const Padding(
                                padding: EdgeInsets.all(22),
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.camera,
                                size: 36,
                                color: Colors.black87,
                              ),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _scanning ? null : _scanDemoAsset,
                      icon: const Icon(Icons.pets),
                      label: const Text('Practice cat'),
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter({required this.box, required this.ready});

  final DetectionBox box;
  final bool ready;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      box.left * size.width,
      box.top * size.height,
      box.right * size.width,
      box.bottom * size.height,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = ready ? const Color(0xFF86EFAC) : const Color(0xFFFDBA74);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _BoxPainter oldDelegate) =>
      oldDelegate.box != box || oldDelegate.ready != ready;
}
