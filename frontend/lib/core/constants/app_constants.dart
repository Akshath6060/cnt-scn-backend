/// Application-wide tuning constants.
///
/// Values that materially affect recognition quality are grouped here so they
/// can be tuned without hunting through service code.
library;

class AppConstants {
  const AppConstants._();

  static const String appName = 'Contact Scanner';

  // ── Asset locations (§6, §7) ─────────────────────────────────────────────
  static const String textDetectorAsset = 'assets/models/text_detector.tflite';
  static const String recognizerAsset =
      'assets/models/handwriting_recognizer.tflite';
  static const String combinedAsset = 'assets/models/contact_recognition.tflite';
  static const String charsetAsset = 'assets/models/chars.txt';

  // ── Recognizer input contract (must match the training pipeline) ─────────
  static const int recognizerInputHeight = 32;
  static const int recognizerInputWidth = 800;
  static const int recognizerInputChannels = 3;

  /// Index reserved for the CTC blank symbol in the trained charset.
  static const int ctcBlankIndex = 0;

  // ── Imaging ──────────────────────────────────────────────────────────────
  /// Long-edge size used for document/edge detection. Detection runs on a
  /// downscaled copy for speed; coordinates are mapped back to full
  /// resolution before cropping (§24).
  static const int detectionLongEdge = 1024;

  /// Maximum long edge retained for the flattened document. Large enough to
  /// keep handwriting legible for the recognizer, small enough to bound memory.
  static const int documentMaxLongEdge = 2200;

  // ── Quality thresholds (§26) ─────────────────────────────────────────────
  /// Variance-of-Laplacian below this is reported as blurry.
  static const double blurVarianceThreshold = 90.0;
  static const double darkMeanThreshold = 62.0;
  static const double brightMeanThreshold = 205.0;

  /// Fraction of frame the document must cover before we stop warning
  /// "document too far away".
  static const double minDocumentAreaRatio = 0.18;

  // ── Storage ──────────────────────────────────────────────────────────────
  static const String databaseName = 'contact_scanner.db';
  static const int databaseVersion = 1;
  static const String scanWorkingDirName = 'scan_working';

  // ── Background cleanup (§15) ─────────────────────────────────────────────
  static const String cleanupTaskName = 'contact_scanner.expiry_cleanup';
  static const String cleanupTaskUniqueName = 'contact_scanner.expiry_cleanup.periodic';
  static const Duration cleanupInterval = Duration(minutes: 15);

  /// Max consecutive failures before a record stops being retried
  /// automatically and is surfaced to the user instead.
  static const int maxCleanupRetries = 5;
}
