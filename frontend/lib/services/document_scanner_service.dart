
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../core/constants/app_constants.dart';
import '../core/errors/app_exceptions.dart';
import '../core/utils/redaction.dart';
import '../imaging/dart_image_processor.dart';
import '../imaging/document_image_processor.dart';
import '../models/bounding_box.dart';
import '../models/document_scan.dart';
import '../models/quality_report.dart';

/// Outcome of running detection over a captured frame.
class DocumentDetectionResult {
  const DocumentDetectionResult({
    required this.corners,
    required this.imageWidth,
    required this.imageHeight,
    required this.wasAutoDetected,
    required this.quality,
  });

  /// Detected page quad, or the full frame when detection failed — the user
  /// then adjusts the corners by hand (§4).
  final DocumentCorners corners;

  final int imageWidth;
  final int imageHeight;
  final bool wasAutoDetected;
  final QualityReport quality;
}

/// Phase 1: camera capture alignment (§4).
///
/// Every heavy operation is dispatched to a background isolate through
/// [compute] so the camera preview and UI never stall (§24).
class DocumentScannerService {
  DocumentScannerService({DocumentImageProcessor? processor})
      : _processor = processor ?? const DartImageProcessor();

  final DocumentImageProcessor _processor;

  static const _tag = 'DocumentScanner';

  String get backendName => _processor.backendName;

  /// Detects the document in an encoded camera frame.
  ///
  /// Never throws for "no page found": that is reported as
  /// `wasAutoDetected == false` with full-frame corners, so the user can
  /// place them manually instead of hitting a dead end (§4, §25).
  Future<DocumentDetectionResult> detectDocument(Uint8List imageBytes) async {
    try {
      return await compute(_detectDocumentIsolate, imageBytes);
    } catch (e, s) {
      AppLog.error(_tag, 'detection failed', e, s);
      throw ImageProcessingException(
        AppErrorCode.documentNotDetected,
        ImageProcessingException.documentNotDetected.userMessage,
        cause: e,
        stackTrace: s,
      );
    }
  }

  /// Corner detection alone, for the manual-adjustment editor.
  Future<DocumentCorners?> findDocumentCorners(Uint8List imageBytes) async {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return null;
    return _processor.findDocumentCorners(decoded);
  }

  /// Flattens the page using [corners] (which may have been edited by hand).
  Future<AlignedDocument> applyPerspectiveTransform(
    Uint8List imageBytes,
    DocumentCorners corners, {
    bool deskew = true,
  }) async {
    try {
      return await compute(
        _warpIsolate,
        _WarpRequest(imageBytes: imageBytes, corners: corners, deskew: deskew),
      );
    } catch (e, s) {
      AppLog.error(_tag, 'perspective transform failed', e, s);
      throw ImageProcessingException(
        AppErrorCode.preprocessingFailed,
        'The page could not be flattened. Try adjusting the corners.',
        cause: e,
        stackTrace: s,
      );
    }
  }

  /// Rotates an encoded document by a quarter turn (§4 automatic rotation).
  Future<Uint8List> rotateDocument(Uint8List imageBytes, int quarterTurns) async =>
      compute(
        _rotateIsolate,
        _RotateRequest(imageBytes: imageBytes, quarterTurns: quarterTurns),
      );

  /// Crops an encoded document to [box].
  Future<Uint8List> cropDocument(Uint8List imageBytes, BoundingBox box) async =>
      compute(
        _cropIsolate,
        _CropRequest(imageBytes: imageBytes, box: box),
      );

  /// Straightens a document whose text lines are not level.
  Future<Uint8List> deskewDocument(Uint8List imageBytes) async =>
      compute(_deskewIsolate, imageBytes);
}

// ── Isolate entry points ────────────────────────────────────────────────────
// Top-level so they can be sent to a background isolate. Each reconstructs a
// stateless processor rather than capturing one.

DocumentDetectionResult _detectDocumentIsolate(Uint8List bytes) {
  const processor = DartImageProcessor();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const ImageProcessingException(
      AppErrorCode.captureFailed,
      'The captured photo could not be read.',
    );
  }

  final corners = processor.findDocumentCorners(decoded);
  final frameArea = (decoded.width * decoded.height).toDouble();
  final ratio = corners == null ? 0.0 : (corners.area / frameArea).clamp(0.0, 1.0);

  return DocumentDetectionResult(
    corners: corners ?? DocumentCorners.fullFrame(decoded.width, decoded.height),
    imageWidth: decoded.width,
    imageHeight: decoded.height,
    wasAutoDetected: corners != null,
    quality: processor.assessQuality(decoded, documentAreaRatio: ratio),
  );
}

class _WarpRequest {
  const _WarpRequest({
    required this.imageBytes,
    required this.corners,
    required this.deskew,
  });
  final Uint8List imageBytes;
  final DocumentCorners corners;
  final bool deskew;
}

AlignedDocument _warpIsolate(_WarpRequest request) {
  const processor = DartImageProcessor();
  final decoded = img.decodeImage(request.imageBytes);
  if (decoded == null) {
    throw const ImageProcessingException(
      AppErrorCode.captureFailed,
      'The captured photo could not be read.',
    );
  }

  var flattened = processor.applyPerspectiveTransform(decoded, request.corners);
  if (request.deskew) {
    flattened = processor.deskewDocument(flattened);
  }

  final frameArea = (decoded.width * decoded.height).toDouble();
  final ratio = (request.corners.area / frameArea).clamp(0.0, 1.0);

  return AlignedDocument(
    imageBytes: Uint8List.fromList(img.encodeJpg(flattened, quality: 90)),
    width: flattened.width,
    height: flattened.height,
    corners: request.corners,
    wasAutoDetected: true,
    quality: processor.assessQuality(flattened, documentAreaRatio: ratio),
  );
}

class _RotateRequest {
  const _RotateRequest({required this.imageBytes, required this.quarterTurns});
  final Uint8List imageBytes;
  final int quarterTurns;
}

Uint8List _rotateIsolate(_RotateRequest request) {
  const processor = DartImageProcessor();
  final decoded = img.decodeImage(request.imageBytes);
  if (decoded == null) return request.imageBytes;
  final rotated = processor.rotateQuarterTurns(decoded, request.quarterTurns);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 90));
}

class _CropRequest {
  const _CropRequest({required this.imageBytes, required this.box});
  final Uint8List imageBytes;
  final BoundingBox box;
}

Uint8List _cropIsolate(_CropRequest request) {
  const processor = DartImageProcessor();
  final decoded = img.decodeImage(request.imageBytes);
  if (decoded == null) return request.imageBytes;
  final cropped = processor.cropDocument(decoded, request.box);
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 90));
}

Uint8List _deskewIsolate(Uint8List bytes) {
  const processor = DartImageProcessor();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final straightened = processor.deskewDocument(decoded);
  return Uint8List.fromList(img.encodeJpg(straightened, quality: 90));
}

/// Keeps the long-edge cap discoverable next to the code that enforces it.
const int kDocumentMaxLongEdge = AppConstants.documentMaxLongEdge;
