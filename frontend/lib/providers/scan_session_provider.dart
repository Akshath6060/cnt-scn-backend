import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exceptions.dart';
import '../imaging/document_image_processor.dart';
import '../models/document_scan.dart';
import '../models/processing_result.dart';
import '../services/contact_scan_pipeline.dart';
import '../services/document_scanner_service.dart';
import '../services/settings_service.dart';
import '../services/temp_file_service.dart';
import 'app_providers.dart';

/// Where the user is in the scan flow.
enum ScanPhase { idle, captured, aligning, aligned, processing, complete, failed }

/// State of one scan, from capture through to a reviewable result.
@immutable
class ScanSessionState {
  const ScanSessionState({
    this.phase = ScanPhase.idle,
    this.captureBytes,
    this.detection,
    this.corners,
    this.alignedDocument,
    this.progress,
    this.result,
    this.error,
    this.debugStages,
  });

  final ScanPhase phase;

  /// Raw capture. Held in memory only; never written to the gallery (§19).
  final Uint8List? captureBytes;

  final DocumentDetectionResult? detection;

  /// Live corner positions, which the user may drag (§4).
  final DocumentCorners? corners;

  final AlignedDocument? alignedDocument;
  final ProcessingProgress? progress;
  final ContactExtractionResult? result;
  final AppException? error;
  final PreprocessingDebugStages? debugStages;

  bool get isBusy =>
      phase == ScanPhase.aligning || phase == ScanPhase.processing;

  ScanSessionState copyWith({
    ScanPhase? phase,
    Uint8List? captureBytes,
    DocumentDetectionResult? detection,
    DocumentCorners? corners,
    AlignedDocument? alignedDocument,
    ProcessingProgress? progress,
    ContactExtractionResult? result,
    AppException? error,
    bool clearError = false,
    PreprocessingDebugStages? debugStages,
  }) =>
      ScanSessionState(
        phase: phase ?? this.phase,
        captureBytes: captureBytes ?? this.captureBytes,
        detection: detection ?? this.detection,
        corners: corners ?? this.corners,
        alignedDocument: alignedDocument ?? this.alignedDocument,
        progress: progress ?? this.progress,
        result: result ?? this.result,
        error: clearError ? null : (error ?? this.error),
        debugStages: debugStages ?? this.debugStages,
      );
}

/// Drives one scan through the pipeline (§3, §20).
class ScanSessionNotifier extends StateNotifier<ScanSessionState> {
  ScanSessionNotifier({
    required DocumentScannerService scanner,
    required Future<ContactScanPipeline> Function() pipeline,
    required TempFileService tempFiles,
    required AppSettings Function() settings,
  })  : _scanner = scanner,
        _pipeline = pipeline,
        _tempFiles = tempFiles,
        _settings = settings,
        super(const ScanSessionState());

  final DocumentScannerService _scanner;
  final Future<ContactScanPipeline> Function() _pipeline;
  final TempFileService _tempFiles;
  final AppSettings Function() _settings;

  bool _cancelled = false;

  /// Accepts a freshly captured frame and runs document detection.
  Future<void> onCaptured(Uint8List bytes) async {
    _cancelled = false;
    state = ScanSessionState(
      phase: ScanPhase.aligning,
      captureBytes: bytes,
    );

    try {
      final detection = await _scanner.detectDocument(bytes);
      state = state.copyWith(
        phase: ScanPhase.captured,
        detection: detection,
        corners: detection.corners,
      );
    } on AppException catch (e) {
      state = state.copyWith(phase: ScanPhase.failed, error: e);
    }
  }

  /// Updates one dragged corner (§4 manual adjustment).
  void updateCorner(int index, Point position) {
    final current = state.corners;
    final detection = state.detection;
    if (current == null || detection == null) return;

    final clamped = position.clampTo(
      detection.imageWidth.toDouble(),
      detection.imageHeight.toDouble(),
    );
    state = state.copyWith(corners: current.replace(index, clamped));
  }

  /// Resets the corners to the automatic detection.
  void resetCorners() {
    final detection = state.detection;
    if (detection != null) state = state.copyWith(corners: detection.corners);
  }

  /// Flattens the page using the current corners.
  Future<void> alignDocument() async {
    final bytes = state.captureBytes;
    final corners = state.corners;
    if (bytes == null || corners == null) return;

    state = state.copyWith(phase: ScanPhase.aligning, clearError: true);
    try {
      final aligned = await _scanner.applyPerspectiveTransform(bytes, corners);
      state = state.copyWith(
        phase: ScanPhase.aligned,
        alignedDocument: aligned,
      );
    } on AppException catch (e) {
      state = state.copyWith(phase: ScanPhase.failed, error: e);
    }
  }

  /// Runs recognition and extraction.
  Future<void> process() async {
    final document = state.alignedDocument;
    if (document == null) return;

    _cancelled = false;
    state = state.copyWith(
      phase: ScanPhase.processing,
      clearError: true,
      progress: const ProcessingProgress(ProcessingStage.preparingImage),
    );

    try {
      final pipeline = await _pipeline();
      final settings = _settings();

      final result = await pipeline.process(
        document,
        preprocessingOptions: PreprocessingOptions(
          // Debug stages cost memory and time, so they are captured only when
          // the developer preview is switched on (§5).
          captureDebugStages: settings.showDebugPreview,
        ),
        onProgress: (progress) {
          if (!mounted) return;
          state = state.copyWith(progress: progress);
        },
        isCancelled: () => _cancelled,
      );

      if (!mounted) return;
      state = state.copyWith(phase: ScanPhase.complete, result: result);

      // The scan is done: drop the working images unless the user asked to
      // keep them (§19).
      if (!settings.keepScannedImages) {
        await _tempFiles.clearWorkingDirectory();
      }
    } on AppException catch (e) {
      if (!mounted) return;
      state = state.copyWith(phase: ScanPhase.failed, error: e);
      await _tempFiles.clearWorkingDirectory();
    } catch (e, s) {
      if (!mounted) return;
      state = state.copyWith(
        phase: ScanPhase.failed,
        error: AppException(
          AppErrorCode.unknown,
          'Something went wrong while reading this page.',
          cause: e,
          stackTrace: s,
        ),
      );
      await _tempFiles.clearWorkingDirectory();
    }
  }

  /// Requests cancellation; the pipeline stops at its next stage boundary.
  void cancel() => _cancelled = true;

  /// Clears the session and removes any temporary files (§19).
  Future<void> reset() async {
    _cancelled = true;
    state = const ScanSessionState();
    await _tempFiles.clearWorkingDirectory();
  }
}

final scanSessionProvider =
    StateNotifierProvider<ScanSessionNotifier, ScanSessionState>(
  (ref) => ScanSessionNotifier(
    scanner: ref.watch(documentScannerProvider),
    pipeline: () => ref.read(scanPipelineProvider.future),
    tempFiles: ref.watch(tempFileServiceProvider),
    settings: () =>
        ref.read(settingsProvider).valueOrNull ?? const AppSettings(),
  ),
);
