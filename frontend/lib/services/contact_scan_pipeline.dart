import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../core/errors/app_exceptions.dart';
import '../core/utils/redaction.dart';
import '../imaging/document_image_processor.dart';
import '../ml/handwriting_recognizer.dart';
import '../ml/text_detector.dart';
import '../models/contact_candidate.dart';
import '../models/document_scan.dart';
import '../models/processing_result.dart';
import '../models/recognized_text.dart';
import 'contact_extraction_service.dart';
import 'document_scanner_service.dart';
import 'image_preprocessing_service.dart';
import 'spatial_contact_pairing_service.dart';

/// Orchestrates the whole local pipeline (§20, §36).
///
/// Each stage is a separate collaborator, so any one of them can be swapped
/// without touching the others (§35). The pipeline itself only sequences the
/// work, reports progress, and converts failures into typed errors.
class ContactScanPipeline {
  ContactScanPipeline({
    required DocumentScannerService scanner,
    required ImagePreprocessingService preprocessor,
    required TextDetector textDetector,
    required HandwritingRecognizer recognizer,
    this.extractor = const ContactExtractionService(),
    this.pairing = const SpatialContactPairingService(),
  })  : _scanner = scanner,
        _preprocessor = preprocessor,
        _textDetector = textDetector,
        _recognizer = recognizer;

  final DocumentScannerService _scanner;
  final ImagePreprocessingService _preprocessor;
  final TextDetector _textDetector;
  final HandwritingRecognizer _recognizer;
  final ContactExtractionService extractor;
  final SpatialContactPairingService pairing;

  static const _tag = 'ScanPipeline';

  /// Runs alignment for a freshly captured frame (§20 `captureDocument` →
  /// `alignDocument`).
  Future<DocumentDetectionResult> alignDocument(Uint8List captureBytes) =>
      _scanner.detectDocument(captureBytes);

  /// Flattens the page once the user has confirmed or adjusted the corners.
  Future<AlignedDocument> flattenDocument(
    Uint8List captureBytes,
    DocumentCorners corners,
  ) =>
      _scanner.applyPerspectiveTransform(captureBytes, corners);

  /// Runs preprocessing → detection → recognition → extraction → pairing.
  ///
  /// [onProgress] receives a [ProcessingProgress] for each stage; the
  /// recognition stage additionally reports per-region counts, which is the
  /// only place a genuine percentage exists (§23).
  ///
  /// [isCancelled] is polled between stages so a user leaving the screen stops
  /// the work rather than letting it run to completion in the background.
  Future<ContactExtractionResult> process(
    AlignedDocument document, {
    void Function(ProcessingProgress progress)? onProgress,
    bool Function()? isCancelled,
    PreprocessingOptions preprocessingOptions = const PreprocessingOptions(),
  }) async {
    void report(ProcessingStage stage, {String? detail, int? done, int? total}) =>
        onProgress?.call(ProcessingProgress(
          stage,
          detail: detail,
          itemsDone: done,
          itemsTotal: total,
        ));

    void checkCancelled() {
      if (isCancelled?.call() ?? false) throw const CancelledException();
    }

    // ── 1. Preprocess ────────────────────────────────────────────────────
    report(ProcessingStage.preparingImage);
    final preprocessed = await _preprocessor.preprocess(
      document.imageBytes,
      options: preprocessingOptions,
    );
    checkCancelled();

    // Detection runs on the binarised page; recognition reads the greyscale
    // copy, which preserves the stroke gradients a CRNN was trained on.
    final binarised = img.decodeImage(preprocessed.processedBytes);
    final greyscale = img.decodeImage(preprocessed.grayscaleBytes);
    if (binarised == null || greyscale == null) {
      throw const ImageProcessingException(
        AppErrorCode.preprocessingFailed,
        'The prepared page could not be read.',
      );
    }

    // ── 2. Detect text regions ───────────────────────────────────────────
    report(ProcessingStage.detectingText);
    final regions = (await _textDetector.detect(binarised)).deduplicated();
    checkCancelled();

    if (regions.isEmpty) {
      AppLog.info(_tag, 'no text regions detected');
      throw const AppException(
        AppErrorCode.noTextDetected,
        'No handwriting was found on this page. '
        'Try a sharper photo, or check that the sheet is fully in frame.',
      );
    }
    AppLog.info(_tag, 'detected ${regions.length} text region(s)');

    // ── 3. Recognise handwriting ─────────────────────────────────────────
    report(
      ProcessingStage.recognizingHandwriting,
      done: 0,
      total: regions.length,
    );

    final recognised = await _recognizer.recognize(
      greyscale,
      regions,
      onProgress: (done, total) => report(
        ProcessingStage.recognizingHandwriting,
        done: done,
        total: total,
      ),
    );
    checkCancelled();

    if (recognised.isEmpty) {
      throw const AppException(
        AppErrorCode.noTextDetected,
        'The handwriting on this page could not be read. '
        'Try better lighting or a closer photo.',
      );
    }

    // ── 4. Classify entities and parse phone numbers ─────────────────────
    report(ProcessingStage.findingPhoneNumbers);
    final candidates = extractor.classify(recognised);
    checkCancelled();

    final phones = candidates.where((c) => c.isPhone).toList();
    if (phones.isEmpty) {
      // Not fatal: names alone are still worth showing so the user can type
      // the numbers in rather than rescanning (§9 "do not silently discard").
      AppLog.info(_tag, 'no phone numbers detected');
    }

    // ── 5. Spatial pairing ───────────────────────────────────────────────
    report(ProcessingStage.matchingNames);
    final outcome = pairing.pair(
      candidates,
      documentWidth: preprocessed.width.toDouble(),
      documentHeight: preprocessed.height.toDouble(),
    );
    checkCancelled();

    // ── 6. Validate and assemble the reviewable result ───────────────────
    report(ProcessingStage.preparingContacts);
    final result = ContactExtractionResult(
      contacts: outcome.contacts,
      unmatchedNames: outcome.unmatchedNames,
      unmatchedPhones: outcome.unmatchedPhones,
      ignoredEntities:
          candidates.where((c) => c.entityType.isIgnorable).toList(),
      recognizedText: recognised,
      quality: document.quality,
      usedMockRecognizer: _recognizer.isMock,
    );

    report(ProcessingStage.done);
    AppLog.info(
      _tag,
      'pipeline produced ${result.contacts.length} contact(s), '
      '${result.unmatchedNames.length} unmatched name(s), '
      '${result.unmatchedPhones.length} unmatched number(s)',
    );
    return result;
  }

  /// Convenience used by tests and by any caller that already holds OCR
  /// output: runs only the extraction half of the pipeline.
  ContactExtractionResult extractFromRecognizedText(
    List<RecognizedText> recognised, {
    required double documentWidth,
    required double documentHeight,
    bool usedMock = false,
  }) {
    final candidates = extractor.classify(recognised);
    final outcome = pairing.pair(
      candidates,
      documentWidth: documentWidth,
      documentHeight: documentHeight,
    );
    return ContactExtractionResult(
      contacts: outcome.contacts,
      unmatchedNames: outcome.unmatchedNames,
      unmatchedPhones: outcome.unmatchedPhones,
      ignoredEntities:
          candidates.where((c) => c.entityType.isIgnorable).toList(),
      recognizedText: recognised,
      usedMockRecognizer: usedMock,
    );
  }

  /// Releases detector and recogniser resources (§24).
  Future<void> dispose() async {
    await _textDetector.dispose();
    await _recognizer.dispose();
  }
}

/// Convenience view over candidates for the review screen's manual pairing.
extension ContactCandidateListX on List<ContactCandidate> {
  List<ContactCandidate> get namesOnly => where((c) => c.isName).toList();
  List<ContactCandidate> get phonesOnly => where((c) => c.isPhone).toList();
}
