import '../models/phone_number.dart';

/// Deterministic, offline telephone-number parser (§8.2).
///
/// The parser is intentionally conservative: it will happily report
/// `isValid == false` rather than invent a plausible number, because a wrong
/// number saved to the phonebook is worse than one the user has to retype.
///
/// No network, no `libphonenumber`, no locale database — just rules.
class PhoneNumberParser {
  const PhoneNumberParser({this.defaultCountryCode = '+91'});

  /// Country code assumed for bare national numbers. Only ever *added* to the
  /// normalised value; a number that already carries a country code keeps it
  /// (§8.2 "do not destroy valid international numbers").
  final String defaultCountryCode;

  /// Characters that legitimately appear between digits.
  static final RegExp _separators = RegExp(r'[\s\-().–—/\\]+');

  /// OCR confusions worth repairing inside a phone field (§8.3).
  ///
  /// Deliberately small. Every entry is a glyph that is *visually* a digit in
  /// handwriting; anything more aggressive starts corrupting real names.
  static const Map<String, String> ocrDigitSubstitutions = {
    'O': '0', 'o': '0', 'Q': '0', 'D': '0',
    'I': '1', 'l': '1', 'i': '1', '|': '1', '!': '1',
    'Z': '2', 'z': '2',
    'E': '3',
    'A': '4',
    'S': '5', 's': '5',
    'G': '6', 'b': '6',
    'T': '7', 'r': '7',
    'B': '8',
    'g': '9', 'q': '9',
  };

  /// Longest-first so that '+1' never shadows '+91'.
  static const List<String> _knownCountryCodes = [
    '971', '966', '977', '880', '974', '968', '965', '962', '960',
    '353', '351', '358', '380', '386',
    '852', '853', '855', '856',
    '212', '213', '216', '218', '234', '254', '255', '256', '260', '263',
    '91', '92', '93', '94', '95', '98',
    '20', '27', '30', '31', '32', '33', '34', '36', '39',
    '40', '41', '43', '44', '45', '46', '47', '48', '49',
    '51', '52', '53', '54', '55', '56', '57', '58',
    '60', '61', '62', '63', '64', '65', '66',
    '81', '82', '84', '86',
    '1', '7',
  ];

  // ── Public API ────────────────────────────────────────────────────────────

  /// Parses [raw] into a [ParsedPhoneNumber].
  ///
  /// Returns a value with `isValid == false` when [raw] cannot be read as a
  /// telephone number; callers must check rather than assume.
  ParsedPhoneNumber parse(String raw) {
    final original = raw.trim();
    if (original.isEmpty) {
      return _invalid(original, 0);
    }

    // Repair OCR glyphs only when the field already looks numeric (§8.3).
    final corrections = <String>[];
    final repaired = looksLikePhone(original)
        ? _applyOcrCorrections(original, corrections)
        : original;

    // Keep '+' only if it leads, then drop every separator.
    final hasPlus = repaired.trimLeft().startsWith('+');
    var digits = repaired.replaceAll(_separators, '').replaceAll('+', '');

    // '00' is the international access prefix — treat it as '+'.
    var international = hasPlus;
    if (!international && digits.startsWith('00') && digits.length > 10) {
      international = true;
      digits = digits.substring(2);
    }

    if (digits.isEmpty || !RegExp(r'^\d+$').hasMatch(digits)) {
      return _invalid(original, 0, corrections: corrections);
    }

    return international
        ? _parseInternational(original, digits, corrections)
        : _parseNational(original, digits, corrections);
  }

  /// Cheap gate used both by [parse] and by entity classification (§8.1).
  ///
  /// True when the string is dominated by digits and phone punctuation, and
  /// any letters present are all plausible digit misreads.
  bool looksLikePhone(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;

    var digitCount = 0;
    var confusableLetters = 0;
    var otherLetters = 0;
    var punctuation = 0;

    for (final ch in trimmed.split('')) {
      if (RegExp(r'\d').hasMatch(ch)) {
        digitCount++;
      } else if (RegExp(r'[A-Za-z]').hasMatch(ch)) {
        if (ocrDigitSubstitutions.containsKey(ch)) {
          confusableLetters++;
        } else {
          otherLetters++;
        }
      } else if (RegExp(r'[\s\-+().|!/\\]').hasMatch(ch)) {
        punctuation++;
      } else {
        otherLetters++;
      }
    }

    // A single unmistakable non-digit letter disqualifies the string: that is
    // what stops "Anu 5" being read as a number.
    if (otherLetters > 0) return false;

    final numericish = digitCount + confusableLetters;
    if (numericish < 6) return false;

    // Confusable letters may not outnumber real digits.
    if (confusableLetters > digitCount) return false;

    // Guard against long alphabetic strings made purely of confusables
    // (e.g. "SOS" or "Lisa" -> 'l','i','s','a' are all confusable).
    if (digitCount < 4) return false;

    final total = digitCount + confusableLetters + punctuation;
    return total > 0 && numericish / total >= 0.5;
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  String _applyOcrCorrections(String value, List<String> log) {
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final ch = value[i];
      final replacement = ocrDigitSubstitutions[ch];
      if (replacement != null) {
        buffer.write(replacement);
        log.add('$ch->$replacement @$i');
      } else {
        buffer.write(ch);
      }
    }
    return buffer.toString();
  }

  ParsedPhoneNumber _parseInternational(
    String original,
    String digits,
    List<String> corrections,
  ) {
    for (final code in _knownCountryCodes) {
      if (!digits.startsWith(code)) continue;
      final national = digits.substring(code.length);
      if (national.length < 6 || national.length > 12) continue;

      final valid = _isPlausibleNational(national, '+$code');
      return ParsedPhoneNumber(
        originalValue: original,
        normalizedValue: '+$code$national',
        countryCode: '+$code',
        nationalNumber: national,
        isValid: valid,
        confidence: _score(
          valid: valid,
          hadCountryCode: true,
          corrections: corrections.length,
          nationalLength: national.length,
        ),
        appliedOcrCorrections: corrections,
      );
    }

    // Unknown calling code: keep the number intact rather than mangling it.
    final valid = digits.length >= 8 && digits.length <= 15;
    return ParsedPhoneNumber(
      originalValue: original,
      normalizedValue: '+$digits',
      countryCode: null,
      nationalNumber: digits,
      isValid: valid,
      confidence: valid ? 0.55 : 0.2,
      appliedOcrCorrections: corrections,
    );
  }

  ParsedPhoneNumber _parseNational(
    String original,
    String digits,
    List<String> corrections,
  ) {
    var national = digits;

    // Strip a single national trunk prefix ('0') ahead of a 10-digit number.
    var strippedTrunk = false;
    if (national.length == 11 && national.startsWith('0')) {
      national = national.substring(1);
      strippedTrunk = true;
    }

    // A bare 12-digit string beginning with a country code but no '+'
    // (e.g. "919876543210") is still an Indian mobile.
    if (national.length == 12 && national.startsWith('91')) {
      final candidate = national.substring(2);
      if (_isIndianMobile(candidate)) {
        return ParsedPhoneNumber(
          originalValue: original,
          normalizedValue: '+91$candidate',
          countryCode: '+91',
          nationalNumber: candidate,
          isValid: true,
          confidence: _score(
            valid: true,
            hadCountryCode: true,
            corrections: corrections.length,
            nationalLength: 10,
          ),
          appliedOcrCorrections: corrections,
        );
      }
    }

    final valid = _isPlausibleNational(national, defaultCountryCode);

    // Attach the default country code only to numbers we actually believe in.
    final normalized =
        valid && national.length == 10 ? '$defaultCountryCode$national' : national;

    return ParsedPhoneNumber(
      originalValue: original,
      normalizedValue: normalized,
      countryCode: valid && national.length == 10 ? defaultCountryCode : null,
      nationalNumber: national,
      isValid: valid,
      confidence: _score(
        valid: valid,
        hadCountryCode: false,
        corrections: corrections.length,
        nationalLength: national.length,
        trunkStripped: strippedTrunk,
      ),
      appliedOcrCorrections: corrections,
    );
  }

  /// Indian mobile numbers are 10 digits starting 6–9.
  bool _isIndianMobile(String national) =>
      national.length == 10 && RegExp(r'^[6-9]\d{9}$').hasMatch(national);

  bool _isPlausibleNational(String national, String? countryCode) {
    if (countryCode == '+91') return _isIndianMobile(national);
    // Generic E.164 subscriber-length sanity check.
    return national.length >= 7 && national.length <= 12;
  }

  double _score({
    required bool valid,
    required bool hadCountryCode,
    required int corrections,
    required int nationalLength,
    bool trunkStripped = false,
  }) {
    if (!valid) {
      // Still report a non-zero score: the review screen shows these so the
      // user can repair them rather than losing the data (§9).
      return (0.30 - corrections * 0.03).clamp(0.05, 0.45);
    }
    var score = 0.80;
    if (hadCountryCode) score += 0.10;
    if (nationalLength == 10) score += 0.05;
    if (trunkStripped) score -= 0.03;
    score -= corrections * 0.06; // each repair is a guess
    return score.clamp(0.05, 0.99);
  }

  ParsedPhoneNumber _invalid(
    String original,
    double confidence, {
    List<String> corrections = const [],
  }) =>
      ParsedPhoneNumber(
        originalValue: original,
        normalizedValue: '',
        countryCode: null,
        isValid: false,
        confidence: confidence,
        appliedOcrCorrections: corrections,
      );
}
