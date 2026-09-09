import 'bounding_box.dart';
import 'entity_type.dart';
import 'phone_number.dart';
import 'recognized_text.dart';

/// A classified OCR fragment: recognised text plus the entity decision made
/// about it. This is the input to spatial pairing (§9).
class ContactCandidate {
  const ContactCandidate({
    required this.source,
    required this.entityType,
    required this.classificationConfidence,
    this.phone,
    this.normalizedText,
  });

  final RecognizedText source;
  final EntityType entityType;

  /// How sure the rule engine is about [entityType], in [0, 1].
  final double classificationConfidence;

  /// Populated only when [entityType] is [EntityType.phone].
  final ParsedPhoneNumber? phone;

  /// Cleaned display text — e.g. trimmed, list-bullet stripped — while
  /// [source].text keeps the untouched original.
  final String? normalizedText;

  String get text => normalizedText ?? source.text;
  BoundingBox get box => source.boundingBox;
  double get ocrConfidence => source.confidence;

  bool get isPhone => entityType == EntityType.phone;
  bool get isName => entityType == EntityType.name;

  /// Overall trust in this candidate: OCR quality tempered by how cleanly it
  /// matched its entity rules.
  double get overallConfidence =>
      source.combinedConfidence * 0.6 + classificationConfidence * 0.4;

  ContactCandidate copyWith({
    EntityType? entityType,
    double? classificationConfidence,
    ParsedPhoneNumber? phone,
    String? normalizedText,
  }) =>
      ContactCandidate(
        source: source,
        entityType: entityType ?? this.entityType,
        classificationConfidence:
            classificationConfidence ?? this.classificationConfidence,
        phone: phone ?? this.phone,
        normalizedText: normalizedText ?? this.normalizedText,
      );

  @override
  String toString() =>
      'ContactCandidate(${entityType.name}, conf=${overallConfidence.toStringAsFixed(2)})';
}
