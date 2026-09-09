import 'package:camera/camera.dart' hide CameraException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/utils/redaction.dart';
import '../../providers/app_providers.dart';
import '../../providers/scan_session_provider.dart';
import '../../widgets/app_error_view.dart';
import '../document_preview/document_preview_screen.dart';

/// Live camera capture (§4).
///
/// Camera permission is requested here and nowhere else, at the moment the
/// user starts a scan (§27). The controller is disposed on every exit path
/// (§24).
class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  static const _tag = 'CameraScreen';

  CameraController? _controller;
  AppException? _error;
  bool _isInitialising = true;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialise();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  /// Releases the camera when backgrounded and restores it on resume — holding
  /// it open in the background is both wasteful and, on some devices, fatal.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initialise();
    }
  }

  Future<void> _initialise() async {
    setState(() {
      _isInitialising = true;
      _error = null;
    });

    try {
      await ref.read(permissionServiceProvider).ensureCamera();

      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException.unavailable;

      final rear = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        rear,
        // High rather than max: enough detail for handwriting, without the
        // memory spike a full-sensor frame causes on mid-range devices (§24).
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {
        // Not every device exposes focus control; not worth failing over.
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _isInitialising = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isInitialising = false;
      });
    } catch (e, s) {
      AppLog.error(_tag, 'camera init failed', e, s);
      if (!mounted) return;
      setState(() {
        _error = CameraException.unavailable;
        _isInitialising = false;
      });
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_isCapturing) return;

    setState(() => _isCapturing = true);
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();

      // The plugin writes to a cache path; remove it immediately so the
      // capture exists only in memory and our own scoped storage (§19).
      await ref.read(tempFileServiceProvider).deleteQuietly(file.path);

      if (!mounted) return;
      await ref.read(scanSessionProvider.notifier).onCaptured(bytes);

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const DocumentPreviewScreen(),
        ),
      );
    } catch (e, s) {
      AppLog.error(_tag, 'capture failed', e, s);
      if (!mounted) return;
      setState(() => _error = const CameraException(
            AppErrorCode.captureFailed,
            'The photo could not be taken. Try again.',
          ));
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Scan Contact Sheet'),
      ),
      extendBodyBehindAppBar: true,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final error = _error;
    if (error != null) {
      return Center(
        child: AppErrorView(
          error: error,
          onRetry: _initialise,
          onSecondary: () => Navigator.of(context).pop(),
          secondaryLabel: 'Go back',
        ),
      );
    }

    final controller = _controller;
    if (_isInitialising || controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: 1 / controller.value.aspectRatio,
            child: CameraPreview(controller),
          ),
        ),

        // Framing guide.
        IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 100, 24, 160),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.65),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),

        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 34),
            color: Colors.black.withValues(alpha: 0.55),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Fit the whole sheet inside the frame',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 18),
                _ShutterButton(
                  isBusy: _isCapturing,
                  onPressed: _capture,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.isBusy, required this.onPressed});

  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Capture photo',
      child: GestureDetector(
        onTap: isBusy ? null : onPressed,
        child: Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: Colors.white24, width: 4),
          ),
          child: isBusy
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              : const Icon(Icons.camera_alt, size: 30, color: Colors.black87),
        ),
      ),
    );
  }
}
