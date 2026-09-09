import 'contact_candidate.dart';
import 'extracted_contact.dart';
import 'quality_report.dart';
import 'recognized_text.dart';

/// Ordered stages of the local pipeline, used to drive honest progress
/// reporting (§23 — labels, not invented percentages).
enum ProcessingStage {
  preparingImage('Preparing image…'),
  detectingText('Detecting text…'),
  recognizingHandwriting('Recognising handwriting…'),
  findingPhoneNumbers('Finding phone numbers…'),
  matchingNames('Matching names and numbers…'),
  preparingContacts('Preparing contacts…'),
  done('Done');

  const ProcessingStage(this.message);
  final String message;

  /// Fraction of stages completed. This is a genuine count of finished
  /// pipeline steps, not a synthetic timer.
  double get fractionComplete => index / (ProcessingStage.values.length - 1);
}

/// Progress notification emitted by the pipeline.
class ProcessingProgress {
  const ProcessingProgress(this.stage, {this.detail, this.itemsDone, this.itemsTotal});

  final ProcessingStage stage;
  final String? detail;

  /// Populated during recognition, where per-region progress is genuinely
  /// measurable.
  final int? itemsDone;
  final int? itemsTotal;

  bool get hasItemProgress =>
      itemsDone != null && itemsTotal != null && itemsTotal! > 0;

  double? get itemFraction =>
      hasItemProgress ? itemsDone! / itemsTotal! : null;
}

/// Everything Phase 3–4 produced, including the parts that did *not* pair.
///
/// Unmatched entries are carried through deliberately so the review screen can
/// offer manual pairing rather than silently dropping data (§9).
class ContactExtractionResult {
  const ContactExtractionResult({
    required this.contacts,
    this.unmatchedNames = const [],
    this.unmatchedPhones = const [],
    this.ignoredEntities = const [],
    this.recognizedText = const [],
    this.quality = const QualityReport.ok(),
    this.usedMockRecognizer = false,
  });

  final List<ExtractedContact> contacts;

  /// Names with no phone number on their row.
  final List<ContactCandidate> unmatchedNames;

  /// Phone numbers with no name on their row.
  final List<ContactCandidate> unmatchedPhones;

  /// Emails, addresses, headings and the like — kept for transparency.
  final List<ContactCandidate> ignoredEntities;

  /// Raw OCR output, retained for the debug overlay only.
  final List<RecognizedText> recognizedText;

  final QualityReport quality;

  /// True when results came from [MockHandwritingRecognizer]; the UI must
  /// label these as non-production (§30).
  final bool usedMockRecognizer;

  bool get isEmpty =>
      contacts.isEmpty && unmatchedNames.isEmpty && unmatchedPhones.isEmpty;

  int get needsAttentionCount => contacts.where((c) => c.needsAttention).length;

  ContactExtractionResult copyWith({List<ExtractedContact>? contacts}) =>
      ContactExtractionResult(
        contacts: contacts ?? this.contacts,
        unmatchedNames: unmatchedNames,
        unmatchedPhones: unmatchedPhones,
        ignoredEntities: ignoredEntities,
        recognizedText: recognizedText,
        quality: quality,
        usedMockRecognizer: usedMockRecognizer,
      );
}
