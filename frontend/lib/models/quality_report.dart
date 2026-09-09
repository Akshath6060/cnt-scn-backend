/// A specific, actionable image-quality complaint (§26).
enum QualityIssue {
  blurry('This photo looks blurry.', 'Hold the phone steady and try again.'),
  tooDark('The page looks underexposed.', 'Add more light or move to a brighter spot.'),
  overexposed('The page looks washed out.', 'Reduce glare or move out of direct light.'),
  tooFar('The page fills only a small part of the frame.',
      'Move closer so the sheet fills the viewfinder.'),
  lowContrast('The handwriting barely stands out from the paper.',
      'Try a different angle to reduce shadow.');

  const QualityIssue(this.summary, this.suggestion);

  final String summary;
  final String suggestion;
}

/// Outcome of the cheap pre-flight quality check run on the flattened document.
///
/// The check never blocks the user: it only surfaces "Retake" vs
/// "Continue Anyway" (§26).
class QualityReport {
  const QualityReport({
    required this.issues,
    required this.blurVariance,
    required this.meanLuminance,
    required this.documentAreaRatio,
  });

  const QualityReport.ok()
      : issues = const [],
        blurVariance = double.infinity,
        meanLuminance = 128,
        documentAreaRatio = 1;

  final List<QualityIssue> issues;

  /// Variance of the Laplacian — the standard sharpness proxy.
  final double blurVariance;
  final double meanLuminance;

  /// Detected document area as a fraction of the captured frame.
  final double documentAreaRatio;

  bool get isAcceptable => issues.isEmpty;
  bool get hasWarnings => issues.isNotEmpty;

  /// Most severe issue first — blur dominates because it is the one users can
  /// most reliably fix by retaking.
  QualityIssue? get primaryIssue => issues.isEmpty ? null : issues.first;
}
