import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../core/errors/app_exceptions.dart';
import '../core/utils/redaction.dart';
import '../imaging/dart_image_processor.dart';
import '../imaging/document_image_processor.dart';

/// Result handed on to text detection.
class PreprocessingResult {
  const PreprocessingResult({
    required this.processedBytes,
    required this.grayscaleBytes,
    required this.width,
    required this.height,
    required this.appliedSkewCorrection,
    this.debugStages = const PreprocessingDebugStages(),
  });

  /// Binarised page, used for locating text regions.
  final Uint8List processedBytes;

  /// Deskewed greyscale page. Recognition crops come from here so that the
  /// recogniser sees stroke intensity rather than a hard binary mask.
  final Uint8List grayscaleBytes;

  final int width;
  final int height;
  final double appliedSkewCorrection;
  final PreprocessingDebugStages debugStages;
}

/// Phase 2: the offline preprocessing pipeline (§5).
///
/// Ordering is deliberate and documented in `docs/OPENCV_PIPELINE.md`:
/// grayscale → denoise → illumination correction → blur → adaptive threshold
/// → morphological cleanup → deskew.
class ImagePreprocessingService {
  ImagePreprocessingService({DocumentImageProcessor? processor})
      : _processor = processor ?? const DartImageProcessor();

  final DocumentImageProcessor _processor;

  static const _tag = 'Preprocessing';

  String get backendName => _processor.backendName;

  /// Runs the pipeline on a background isolate.
  Future<PreprocessingResult> preprocess(
    Uint8List documentBytes, {
    PreprocessingOptions options = const PreprocessingOptions(),
  }) async {
    try {
      return await compute(
        _preprocessIsolate,
        _PreprocessRequest(bytes: documentBytes, options: options),
      );
    } catch (e, s) {
      AppLog.error(_tag, 'preprocessing failed', e, s);
      throw ImageProcessingException(
        AppErrorCode.preprocessingFailed,
        'The page could not be prepared for reading. Try retaking the photo.',
        cause: e,
        stackTrace: s,
      );
    }
  }
}

class _PreprocessRequest {
  const _PreprocessRequest({required this.bytes, required this.options});
  final Uint8List bytes;
  final PreprocessingOptions options;
}

PreprocessingResult _preprocessIsolate(_PreprocessRequest request) {
  const processor = DartImageProcessor();
  final decoded = img.decodeImage(request.bytes);
  if (decoded == null) {
    throw const ImageProcessingException(
      AppErrorCode.preprocessingFailed,
      'The page image could not be read.',
    );
  }

  final result = processor.preprocess(decoded, request.options);

  return PreprocessingResult(
    processedBytes:
        Uint8List.fromList(img.encodePng(result.processed)),
    grayscaleBytes:
        Uint8List.fromList(img.encodeJpg(result.grayscale, quality: 92)),
    width: result.width,
    height: result.height,
    appliedSkewCorrection: result.appliedSkewCorrection,
    debugStages: result.debugStages,
  );
}
