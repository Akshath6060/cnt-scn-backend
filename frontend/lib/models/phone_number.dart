/// Result of parsing a raw OCR string as a telephone number (§8.2).
class ParsedPhoneNumber {
  const ParsedPhoneNumber({
    required this.originalValue,
    required this.normalizedValue,
    required this.countryCode,
    required this.isValid,
    required this.confidence,
    this.nationalNumber = '',
    this.appliedOcrCorrections = const [],
  });

  /// Exactly what the recogniser produced.
  final String originalValue;

  /// E.164-style value when a country code is known (`+919876543210`),
  /// otherwise the digits with separators stripped.
  final String normalizedValue;

  /// Country calling code including '+', or `null` when none was present.
  /// A national number is never *invented* a country code (§8.2).
  final String? countryCode;

  final bool isValid;

  /// Parser confidence in [0, 1] — independent of OCR confidence.
  final double confidence;

  /// Subscriber digits without the country code.
  final String nationalNumber;

  /// Human-readable record of OCR repairs, e.g. `['O->0 @2']` (§8.3).
  final List<String> appliedOcrCorrections;

  bool get wasCorrected => appliedOcrCorrections.isNotEmpty;

  /// Digits-only form used for duplicate comparison.
  String get digitsOnly => normalizedValue.replaceAll(RegExp(r'\D'), '');

  /// Last 10 digits — the comparison key that makes `+919876543210`,
  /// `09876543210`, and `9876543210` match one another (§12).
  String get comparisonKey {
    final d = digitsOnly;
    return d.length <= 10 ? d : d.substring(d.length - 10);
  }

  ParsedPhoneNumber copyWith({String? normalizedValue, double? confidence}) =>
      ParsedPhoneNumber(
        originalValue: originalValue,
        normalizedValue: normalizedValue ?? this.normalizedValue,
        countryCode: countryCode,
        isValid: isValid,
        confidence: confidence ?? this.confidence,
        nationalNumber: nationalNumber,
        appliedOcrCorrections: appliedOcrCorrections,
      );

  Map<String, dynamic> toJson() => {
        'originalValue': originalValue,
        'normalizedValue': normalizedValue,
        'countryCode': countryCode,
        'isValid': isValid,
        'confidence': confidence,
      };

  @override
  String toString() =>
      'ParsedPhoneNumber(valid=$isValid, cc=$countryCode, '
      'conf=${confidence.toStringAsFixed(2)})';
}
