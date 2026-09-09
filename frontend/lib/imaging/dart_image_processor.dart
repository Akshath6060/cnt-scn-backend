import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/constants/app_constants.dart';
import '../models/bounding_box.dart';
import '../models/document_scan.dart';
import '../models/quality_report.dart';
import 'document_image_processor.dart';
import 'gray_image.dart';
import 'kernels/contours.dart';
import 'kernels/filters.dart';
import 'kernels/geometry.dart';
import 'kernels/morphology.dart';
import 'kernels/threshold.dart';

/// Pure-Dart implementation of the document pipeline.
///
/// This is the default backend: it needs no native toolchain, runs identically
/// on Android, iOS and the host test VM, and keeps the app fully offline
/// without a build-time SDK download.
class DartImageProcessor implements DocumentImageProcessor {
  const DartImageProcessor();

  @override
  String get backendName => 'Dart imaging kernel';

  // ── Document detection (§4) ──────────────────────────────────────────────

  @override
  DocumentCorners? findDocumentCorners(img.Image source) {
    if (source.width < 32 || source.height < 32) return null;

    // 1. Detect on a downscaled copy — a page boundary is a large-scale
    //    feature, and full resolution buys nothing but latency (§24).
    final longEdge = math.max(source.width, source.height);
    final scale = longEdge > AppConstants.detectionLongEdge
        ? AppConstants.detectionLongEdge / longEdge
        : 1.0;
    final dw = math.max((source.width * scale).round(), 16);
    final dh = math.max((source.height * scale).round(), 16);

    final gray = Filters.resize(GrayImage.fromImage(source), dw, dh);

    // 2. Suppress texture and print so only the paper/background step remains.
    final smoothed = Filters.gaussianBlur(gray, radius: 3);

    // 3. The page is the bright region; invert Otsu so paper is foreground.
    final paperMask = Threshold.otsu(smoothed, inkIsDark: false);

    // 4. Close small gaps (staples, dark print touching an edge) then isolate
    //    the single largest blob, which is the sheet.
    final closed = Morphology.close(paperMask, radiusX: 2, radiusY: 2);
    final mask = Contours.maskOfLargestComponent(closed);

    var inkPixels = 0;
    for (var i = 0; i < mask.length; i++) {
      if (mask.data[i] != 0) inkPixels++;
    }
    // Reject a "page" that is really just background noise.
    final coverage = inkPixels / mask.length;
    if (coverage < 0.10 || coverage > 0.995) return null;

    final corners = Contours.cornersOfMask(mask, 0);
    if (corners == null) return null;

    // 5. Reject implausible quads: a real page is convex-ish and reasonably
    //    filled relative to its own bounding box.
    if (!_isPlausibleQuad(corners, dw, dh)) return null;

    // 6. Map back to full resolution.
    return scale == 1.0 ? corners : corners.scaled(1 / scale);
  }

  /// Rejects degenerate detections before they reach the user.
  bool _isPlausibleQuad(DocumentCorners c, int width, int height) {
    final area = c.area;
    if (area <= 0) return false;

    // Must cover a meaningful share of the frame.
    if (area / (width * height) < 0.10) return false;

    // Each edge must have real length — guards against three-collinear-corner
    // results that would make the homography singular.
    final p = c.points;
    for (var i = 0; i < 4; i++) {
      final a = p[i], b = p[(i + 1) % 4];
      final len = math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
      if (len < math.min(width, height) * 0.15) return false;
    }
    return true;
  }

  // ── Geometric operations ─────────────────────────────────────────────────

  @override
  img.Image applyPerspectiveTransform(img.Image source, DocumentCorners corners) =>
      Geometry.warpPerspective(
        source,
        corners,
        maxLongEdge: AppConstants.documentMaxLongEdge,
      );

  @override
  img.Image rotateDocument(img.Image source, double degrees) =>
      Geometry.rotate(source, degrees);

  @override
  img.Image rotateQuarterTurns(img.Image source, int turns) =>
      Geometry.rotateQuarterTurns(source, turns);

  @override
  img.Image cropDocument(img.Image source, BoundingBox box) {
    final x = box.left.round().clamp(0, source.width - 1);
    final y = box.top.round().clamp(0, source.height - 1);
    final w = box.width.round().clamp(1, source.width - x);
    final h = box.height.round().clamp(1, source.height - y);
    return img.copyCrop(source, x: x, y: y, width: w, height: h);
  }

  @override
  double estimateSkew(img.Image source) {
    final gray = GrayImage.fromImage(source);
    final binary = Threshold.adaptiveMean(gray, offset: 12);
    return Geometry.estimateSkewAngle(binary);
  }

  @override
  img.Image deskewDocument(img.Image source) {
    final angle = estimateSkew(source);
    if (angle.abs() < 0.25) return source;
    // Rotate by the negative of the detected lean to bring lines level.
    return Geometry.rotate(source, -angle);
  }

  // ── Preprocessing pipeline (§5) ──────────────────────────────────────────

  @override
  PreprocessedDocument preprocess(
    img.Image source,
    PreprocessingOptions options,
  ) {
    final debugOriginal =
        options.captureDebugStages ? _encode(source) : null;

    // 1. Grayscale.
    var gray = GrayImage.fromImage(source);
    final debugGray = options.captureDebugStages ? _encode(gray.toImage()) : null;

    // 2. Noise reduction. Median before blur: it removes speckle outright
    //    rather than smearing it into the strokes.
    if (options.denoise) {
      gray = Filters.median3x3(gray);
    }

    // 3. Illumination correction — flattens shadows so a single adaptive pass
    //    behaves consistently across the page.
    if (options.correctIllumination) {
      gray = Filters.correctIllumination(gray);
    }

    // 4. Light Gaussian blur to stabilise the local mean.
    if (options.blurRadius > 0) {
      gray = Filters.gaussianBlur(gray, radius: options.blurRadius);
    }

    // 5. Adaptive threshold (ink = 255).
    var binary = Threshold.adaptiveMean(gray, offset: options.adaptiveOffset);
    final debugThreshold =
        options.captureDebugStages ? _encode(_inkOnWhite(binary)) : null;

    // 6. Optional morphological cleanup. Opening with a 1px radius removes
    //    isolated specks; anything larger starts eating faint strokes, which
    //    §5 explicitly forbids.
    if (options.morphologicalCleanup) {
      binary = Morphology.open(binary, radiusX: 1, radiusY: 1);
    }

    // 7. Deskew last, so the angle is measured on a clean binary image.
    var appliedSkew = 0.0;
    var deskewedGray = gray;
    if (options.deskew) {
      final angle = Geometry.estimateSkewAngle(binary);
      if (angle.abs() >= 0.25) {
        appliedSkew = -angle;
        binary = GrayImage.fromImage(
          Geometry.rotate(_inkOnWhite(binary), appliedSkew),
        );
        // Re-binarise: rotation interpolates, producing intermediate greys.
        binary = Threshold.otsu(binary, inkIsDark: true);
        deskewedGray = GrayImage.fromImage(
          Geometry.rotate(gray.toImage(), appliedSkew),
        );
      }
    }

    final processedImage = _inkOnWhite(binary);
    final debugFinal = options.captureDebugStages ? _encode(processedImage) : null;

    return PreprocessedDocument(
      processed: processedImage,
      grayscale: deskewedGray.toImage(),
      width: binary.width,
      height: binary.height,
      appliedSkewCorrection: appliedSkew,
      debugStages: PreprocessingDebugStages(
        original: debugOriginal,
        grayscale: debugGray,
        thresholded: debugThreshold,
        finalImage: debugFinal,
      ),
    );
  }

  /// Converts the internal "ink = 255" convention into a conventional
  /// black-on-white scan for display and for crop extraction.
  img.Image _inkOnWhite(GrayImage binary) {
    final out = GrayImage(binary.width, binary.height, Uint8List(binary.length));
    for (var i = 0; i < binary.length; i++) {
      out.data[i] = binary.data[i] == 0 ? 255 : 0;
    }
    return out.toImage();
  }

  Uint8List _encode(img.Image image) =>
      Uint8List.fromList(img.encodeJpg(image, quality: 82));

  // ── Quality assessment (§26) ─────────────────────────────────────────────

  @override
  QualityReport assessQuality(
    img.Image source, {
    double documentAreaRatio = 1.0,
  }) {
    // Assess on a downscaled copy: sharpness and exposure are global.
    final longEdge = math.max(source.width, source.height);
    final scale = longEdge > 900 ? 900 / longEdge : 1.0;
    final gray = Filters.resize(
      GrayImage.fromImage(source),
      math.max((source.width * scale).round(), 16),
      math.max((source.height * scale).round(), 16),
    );

    final variance = Filters.laplacianVariance(gray);
    final mean = gray.mean;

    final issues = <QualityIssue>[];

    // Blur first: it is the issue a retake most reliably fixes.
    if (variance < AppConstants.blurVarianceThreshold) {
      issues.add(QualityIssue.blurry);
    }
    if (mean < AppConstants.darkMeanThreshold) {
      issues.add(QualityIssue.tooDark);
    } else if (mean > AppConstants.brightMeanThreshold) {
      issues.add(QualityIssue.overexposed);
    }
    if (documentAreaRatio < AppConstants.minDocumentAreaRatio) {
      issues.add(QualityIssue.tooFar);
    }

    // Low contrast: ink and paper too close together to threshold reliably.
    final level = Threshold.otsuLevel(gray);
    final separation = (mean - level).abs();
    if (separation < 6 && !issues.contains(QualityIssue.blurry)) {
      issues.add(QualityIssue.lowContrast);
    }

    return QualityReport(
      issues: issues,
      blurVariance: variance,
      meanLuminance: mean,
      documentAreaRatio: documentAreaRatio,
    );
  }
}
