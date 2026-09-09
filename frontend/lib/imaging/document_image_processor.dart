import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/bounding_box.dart';
import '../models/document_scan.dart';
import '../models/quality_report.dart';

/// Tunables for the preprocessing pipeline (§5).
class PreprocessingOptions {
  const PreprocessingOptions({
    this.denoise = true,
    this.correctIllumination = true,
    this.blurRadius = 1,
    this.adaptiveOffset = 10,
    this.morphologicalCleanup = true,
    this.deskew = true,
    this.captureDebugStages = false,
  });

  final bool denoise;
  final bool correctIllumination;

  /// Gaussian radius applied before thresholding. Kept deliberately small:
  /// heavy blur erases the faint strokes §5 requires us to preserve.
  final int blurRadius;

  /// Subtracted from the local mean. Higher keeps more faint ink.
  final int adaptiveOffset;

  final bool morphologicalCleanup;
  final bool deskew;

  /// Retains intermediate stages for the developer debug preview (§5).
  /// Never enabled in production by default.
  final bool captureDebugStages;

  PreprocessingOptions copyWith({bool? captureDebugStages}) =>
      PreprocessingOptions(
        denoise: denoise,
        correctIllumination: correctIllumination,
        blurRadius: blurRadius,
        adaptiveOffset: adaptiveOffset,
        morphologicalCleanup: morphologicalCleanup,
        deskew: deskew,
        captureDebugStages: captureDebugStages ?? this.captureDebugStages,
      );
}

/// Intermediate images kept for the debug preview (§5).
class PreprocessingDebugStages {
  const PreprocessingDebugStages({
    this.original,
    this.grayscale,
    this.thresholded,
    this.finalImage,
  });

  final Uint8List? original;
  final Uint8List? grayscale;
  final Uint8List? thresholded;
  final Uint8List? finalImage;

  bool get isEmpty =>
      original == null &&
      grayscale == null &&
      thresholded == null &&
      finalImage == null;
}

/// Output of the preprocessing stage.
class PreprocessedDocument {
  const PreprocessedDocument({
    required this.processed,
    required this.grayscale,
    required this.width,
    required this.height,
    required this.appliedSkewCorrection,
    this.debugStages = const PreprocessingDebugStages(),
  });

  /// Binarised, cleaned image used for text-region detection.
  final img.Image processed;

  /// Deskewed greyscale image. Recognition crops come from *this*, not from
  /// the binarised copy: thresholding discards the stroke-intensity gradients
  /// a CRNN relies on.
  final img.Image grayscale;

  final int width;
  final int height;

  /// Degrees of rotation applied by deskew.
  final double appliedSkewCorrection;

  final PreprocessingDebugStages debugStages;
}

/// The image-processing backend contract (§35 — independently replaceable).
///
/// Two implementations exist:
///   * [DartImageProcessor] — pure Dart, the default. Runs on device *and* in
///     host unit tests, and adds no native build step.
///   * `OpenCvImageProcessor` — delegates to OpenCV via `opencv_dart`.
///     See `docs/OPENCV_PIPELINE.md`.
///
/// Implementations must be pure functions of their inputs so they can run
/// inside a background isolate (§24).
abstract class DocumentImageProcessor {
  /// Shown in Settings so a tester can tell which backend produced a result.
  String get backendName;

  /// Locates the page quadrilateral, or `null` when no plausible page is found.
  ///
  /// Detection runs on a downscaled copy for speed; returned coordinates are
  /// already mapped back to [source]'s resolution (§24).
  DocumentCorners? findDocumentCorners(img.Image source);

  /// Flattens [corners] into a top-down rectangle.
  img.Image applyPerspectiveTransform(img.Image source, DocumentCorners corners);

  /// Rotates by an arbitrary angle, filling exposed area with white.
  img.Image rotateDocument(img.Image source, double degrees);

  /// Quarter-turn rotation for orientation correction.
  img.Image rotateQuarterTurns(img.Image source, int turns);

  /// Crops to [box], clamped to the image bounds.
  img.Image cropDocument(img.Image source, BoundingBox box);

  /// Estimated skew in degrees; positive means the page leans clockwise.
  double estimateSkew(img.Image source);

  /// Rotates by the negative of [estimateSkew].
  img.Image deskewDocument(img.Image source);

  /// The full §5 pipeline.
  PreprocessedDocument preprocess(img.Image source, PreprocessingOptions options);

  /// Cheap pre-flight quality assessment (§26).
  QualityReport assessQuality(img.Image source, {double documentAreaRatio = 1.0});
}
