import 'contact_candidate.dart';
import 'expiry_option.dart';
import 'phone_number.dart';

/// Why a pairing may need human attention (§9 "do not silently discard").
enum PairingIssue {
  /// A name with no phone number on its row.
  unmatchedName,

  /// A phone number with no name on its row.
  unmatchedPhone,

  /// Paired, but the winning score was close to a runner-up.
  ambiguousPairing,

  /// Paired, but OCR confidence on one side is low.
  lowConfidence,

  /// The phone number failed validation.
  invalidPhone,
}

/// A reviewable contact produced by the pipeline and edited by the user (§10).
///
/// Immutable; the review screen replaces entries via [copyWith] so that
/// undo/rebuild stays trivial.
class ExtractedContact {
  ExtractedContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.confidence,
    this.parsedPhone,
    this.nameCandidate,
    this.phoneCandidate,
    this.issues = const {},
    this.isSelected = true,
    this.expiry = const ExpirySelection.permanent(),
    this.wasEditedByUser = false,
  });

  final String id;
  final String name;
  final String phone;

  /// Pairing confidence in [0, 1].
  final double confidence;

  final ParsedPhoneNumber? parsedPhone;
  final ContactCandidate? nameCandidate;
  final ContactCandidate? phoneCandidate;

  final Set<PairingIssue> issues;
  final bool isSelected;
  final ExpirySelection expiry;
  final bool wasEditedByUser;

  bool get isTemporary => expiry.isTemporary;
  bool get hasName => name.trim().isNotEmpty;
  bool get hasPhone => phone.trim().isNotEmpty;

  /// Ready to write to the phonebook.
  bool get isComplete => hasName && hasPhone;

  /// Needs the user's eye before saving.
  bool get needsAttention => issues.isNotEmpty || confidence < 0.65;

  bool get isLowConfidence => confidence < 0.65;

  /// Value written to the phonebook — prefers the normalised form so the
  /// dialer and duplicate checks behave predictably.
  String get phoneForSaving =>
      wasEditedByUser ? phone.trim() : (parsedPhone?.normalizedValue ?? phone.trim());

  ExtractedContact copyWith({
    String? name,
    String? phone,
    double? confidence,
    ParsedPhoneNumber? parsedPhone,
    Set<PairingIssue>? issues,
    bool? isSelected,
    ExpirySelection? expiry,
    bool? wasEditedByUser,
  }) =>
      ExtractedContact(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        confidence: confidence ?? this.confidence,
        parsedPhone: parsedPhone ?? this.parsedPhone,
        nameCandidate: nameCandidate,
        phoneCandidate: phoneCandidate,
        issues: issues ?? this.issues,
        isSelected: isSelected ?? this.isSelected,
        expiry: expiry ?? this.expiry,
        wasEditedByUser: wasEditedByUser ?? this.wasEditedByUser,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'confidence': confidence,
      };

  @override
  String toString() =>
      'ExtractedContact(conf=${confidence.toStringAsFixed(2)}, '
      'issues=${issues.length})';
}
