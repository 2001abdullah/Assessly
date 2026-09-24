import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/omr_frame_analyzer.dart';

/// Live OMR camera. Pops with the captured [File], or null if cancelled.
///
/// The screen analyses the camera stream, draws the detected sheet, tells the
/// user what to fix (distance, tilt, light, focus...) and takes the picture
/// automatically once the sheet is found, sharp and steady. The shutter button
/// always works as a manual fallback.
class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({super.key});

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen>
    with WidgetsBindingObserver {
  /// 1080p: plenty for reading (tests read 100% from 800 px wide images) and
  /// light enough to analyse live. Use ResolutionPreset.high (720p) on very
  /// slow devices.
  static const ResolutionPreset _preset = ResolutionPreset.veryHigh;

  /// Minimum time between analyses.
  static const int _analysisIntervalMs = 110;

  CameraController? _controller;
  final OmrFrameAnalyzer _analyzer = OmrFrameAnalyzer();

  SheetAnalysis _analysis = SheetAnalysis.none;
  String? _error;
  bool _initializing = true;
  bool _capturing = false;
  bool _analyzing = false;
  bool _autoCapture = true;
  bool _torchOn = false;
  int _lastAnalysisMs = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeController();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _disposeController();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initCamera();
    }
  }

  void _disposeController() {
    final c = _controller;
    _controller = null;
    if (c != null) {
      // Fire and forget: dispose stops the stream itself.
      c.dispose();
    }
  }

  // --------------------------------------------------------------------------
  // Camera lifecycle
  // --------------------------------------------------------------------------

  Future<void> _initCamera() async {
    final isRetry = !_initializing;
    _initializing = true;
    _error = null;
    _torchOn = false;
    if (isRetry && mounted) setState(() {});
    try {
      final cameras = await availableCameras();
      final back = cameras
          .where((c) => c.lensDirection == CameraLensDirection.back)
          .toList();
      if (back.isEmpty) {
        throw CameraException('noCamera', 'No back camera was found.');
      }

      final controller = CameraController(
        back.first,
        _preset,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await _tryCamera(() => controller.setFocusMode(FocusMode.auto));
      await _tryCamera(() => controller.setFlashMode(FlashMode.off));

      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      _analyzer.reset();
      await controller.startImageStream(_onFrame);
      if (mounted) setState(() => _initializing = false);
    } on CameraException catch (e) {
      _fail(_describe(e));
    } catch (e) {
      _fail('Could not start the camera ($e).');
    }
  }

  /// Some devices do not support every camera setting; that must not be fatal.
  Future<void> _tryCamera(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('Camera setting not supported: $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _initializing = false;
      _error = message;
    });
  }

  String _describe(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'Camera access is turned off. Allow camera access for '
            'Assessly in your phone settings, or use the system camera below.';
      default:
        return e.description ?? 'The camera could not be started (${e.code}).';
    }
  }

  // --------------------------------------------------------------------------
  // Frame analysis
  // --------------------------------------------------------------------------

  void _onFrame(CameraImage image) {
    if (_analyzing || _capturing || !mounted) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastAnalysisMs < _analysisIntervalMs) return;
    _lastAnalysisMs = nowMs;
    _analyzing = true;
    try {
      final controller = _controller;
      if (controller == null) return;
      final plane = image.planes.first;
      final bgra = image.format.group == ImageFormatGroup.bgra8888;
      // Frames arrive in sensor orientation (landscape). If a platform already
      // hands us upright portrait frames, do not rotate them again.
      final rotation = image.height > image.width
          ? 0
          : controller.description.sensorOrientation;
      final result = _analyzer.analyze(
        LumaFrame(
          bytes: plane.bytes,
          width: image.width,
          height: image.height,
          rowStride: plane.bytesPerRow,
          pixelStride: bgra ? 4 : 1,
          rotation: rotation,
          bgra: bgra,
        ),
      );
      if (!mounted) return;
      setState(() => _analysis = result);
      if (result.ready && _autoCapture) _capture();
    } catch (e, st) {
      debugPrint('Frame analysis failed: $e\n$st');
    } finally {
      _analyzing = false;
    }
  }

  // --------------------------------------------------------------------------
  // Capture
  // --------------------------------------------------------------------------

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing || !controller.value.isInitialized) {
      return;
    }
    setState(() => _capturing = true);
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      HapticFeedback.mediumImpact();
      final XFile shot = await controller.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(File(shot.path));
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _capturing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capture failed: ${e.description ?? e.code}')),
      );
      _analyzer.reset();
      try {
        await controller.startImageStream(_onFrame);
      } catch (_) {}
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final next = !_torchOn;
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchOn = next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This device has no torch.')),
      );
    }
  }

  Future<void> _focusAt(Offset local, Size size) async {
    final controller = _controller;
    if (controller == null) return;
    final point = Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
    await _tryCamera(() => controller.setFocusPoint(point));
    await _tryCamera(() => controller.setExposurePoint(point));
  }

  Future<void> _useSystemCamera() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (file != null && mounted) Navigator.of(context).pop(File(file.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Camera unavailable: $e')));
    }
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------

  static String _hintText(ScanHint hint) {
    switch (hint) {
      case ScanHint.searching:
        return 'Place the whole sheet inside the frame';
      case ScanHint.sideways:
        return 'Turn the sheet upright (portrait)';
      case ScanHint.edge:
        return 'Fit all four corner squares inside the screen';
      case ScanHint.tooFar:
        return 'Move closer';
      case ScanHint.offCenter:
        return 'Center the sheet in the frame';
      case ScanHint.tilted:
        return 'Straighten the sheet';
      case ScanHint.keystone:
        return 'Hold the phone parallel to the sheet';
      case ScanHint.tooDark:
        return 'Too dark: add light or turn on the torch';
      case ScanHint.glare:
        return 'Glare on the sheet: tilt slightly or move the light';
      case ScanHint.unfocused:
        return 'Focusing... hold steady (tap the sheet to focus)';
      case ScanHint.holdStill:
        return 'Hold still...';
      case ScanHint.ready:
        return 'Capturing';
    }
  }

  Color _stateColor() {
    if (_analysis.ready) return Colors.greenAccent;
    if (_analysis.found) return Colors.amberAccent;
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildBody()),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Expanded(
            child: Text(
              'Scan OMR sheet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              _torchOn ? Icons.flash_on : Icons.flash_off,
              color: _torchOn ? Colors.amberAccent : Colors.white,
            ),
            tooltip: 'Torch',
            onPressed: _controller == null ? null : _toggleTorch,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) return _buildError();
    final controller = _controller;
    if (_initializing ||
        controller == null ||
        !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final hint = _analysis.hint;
    final color = _stateColor();

    return Center(
      child: AspectRatio(
        // The preview is landscape internally; show it as portrait.
        aspectRatio: 1 / controller.value.aspectRatio,
        child: LayoutBuilder(
          builder: (context, box) {
            final size = Size(box.maxWidth, box.maxHeight);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _focusAt(d.localPosition, size),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(controller),
                  CustomPaint(painter: _GuidePainter(_analysis, color)),
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: _HintPill(text: _hintText(hint), color: color),
                  ),
                  if (_capturing) const ColoredBox(color: Color(0x66FFFFFF)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 96,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: _autoCapture,
                  onChanged: (v) => setState(() => _autoCapture = v),
                ),
                const Text(
                  'Auto',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: (_controller == null || _capturing) ? null : _capture,
            child: Container(
              width: 74,
              height: 74,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _stateColor(), width: 4),
              ),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 96),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _useSystemCamera,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Use system camera'),
            ),
            TextButton(onPressed: _initCamera, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.9)),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Draws the A4 target frame and, when found, the live outline of the sheet.
class _GuidePainter extends CustomPainter {
  _GuidePainter(this.analysis, this.color);

  final SheetAnalysis analysis;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // A4 target: 92% of the width, never taller than the preview allows.
    var w = size.width * 0.92;
    var h = w * 297 / 210;
    if (h > size.height * 0.94) {
      h = size.height * 0.94;
      w = h * 210 / 297;
    }
    final guide = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: w,
      height: h,
    );

    // dim everything outside the target
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()
        ..addRRect(RRect.fromRectAndRadius(guide, const Radius.circular(10))),
    );
    canvas.drawPath(outside, Paint()..color = const Color(0x55000000));

    // corner brackets
    final bracket = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 30.0;
    void corner(Offset c, double sx, double sy) {
      canvas.drawLine(c, c + Offset(sx * len, 0), bracket);
      canvas.drawLine(c, c + Offset(0, sy * len), bracket);
    }

    corner(guide.topLeft, 1, 1);
    corner(guide.topRight, -1, 1);
    corner(guide.bottomLeft, 1, -1);
    corner(guide.bottomRight, -1, -1);

    // live sheet outline
    if (analysis.found) {
      final pts = [
        for (final p in analysis.corners)
          Offset(p.x * size.width, p.y * size.height),
      ];
      final outline = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (var i = 1; i < 4; i++) {
        outline.lineTo(pts[i].dx, pts[i].dy);
      }
      outline.close();
      canvas.drawPath(
        outline,
        Paint()
          ..color = color.withValues(alpha: 0.18)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        outline,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      for (final p in pts) {
        canvas.drawCircle(p, 6, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) =>
      old.analysis != analysis || old.color != color;
}
