import 'package:contact_scanner/services/phone_number_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = PhoneNumberParser();

  group('formats listed in the specification', () {
    // Every one of these must normalise to the same E.164 value.
    const variants = <String>[
      '9876543210',
      '+91 9876543210',
      '+91 98765 43210',
      '98765 43210',
      '98765-43210',
      '(98765) 43210',
      '+919876543210',
      '09876543210',
      '919876543210',
    ];

    for (final raw in variants) {
      test('"$raw" normalises to +919876543210', () {
        final result = parser.parse(raw);
        expect(result.isValid, isTrue, reason: 'should be valid: $raw');
        expect(result.normalizedValue, '+919876543210');
        expect(result.countryCode, '+91');
        expect(result.nationalNumber, '9876543210');
      });
    }
  });

  group('international numbers are preserved', () {
    test('US number keeps its country code', () {
      final r = parser.parse('+1 415 555 2671');
      expect(r.countryCode, '+1');
      expect(r.nationalNumber, '4155552671');
      expect(r.normalizedValue, '+14155552671');
      expect(r.isValid, isTrue);
    });

    test('UK number is not mangled', () {
      final r = parser.parse('+44 20 7946 0958');
      expect(r.countryCode, '+44');
      expect(r.normalizedValue, '+442079460958');
      expect(r.isValid, isTrue);
    });

    test('00 access prefix is treated as +', () {
      final r = parser.parse('0044 20 7946 0958');
      expect(r.countryCode, '+44');
      expect(r.normalizedValue, '+442079460958');
    });

    test('unknown calling code is retained rather than discarded', () {
      final r = parser.parse('+999 12345678');
      expect(r.normalizedValue, startsWith('+'));
      expect(r.normalizedValue.contains('12345678'), isTrue);
    });
  });

  group('OCR digit repair (§8.3)', () {
    test('O/I/l/S are corrected inside a phone-like field', () {
      final r = parser.parse('9876S4321O');
      expect(r.isValid, isTrue);
      expect(r.nationalNumber, '9876543210');
      expect(r.wasCorrected, isTrue);
      expect(r.appliedOcrCorrections, isNotEmpty);
    });

    test('l and I both become 1', () {
      final r = parser.parse('98765432lI');
      expect(r.nationalNumber, '9876543211');
    });

    test('corrections reduce confidence below a clean read', () {
      final clean = parser.parse('9876543210');
      final repaired = parser.parse('9876S4321O');
      expect(repaired.confidence, lessThan(clean.confidence));
    });

    test('names are never digit-substituted', () {
      // "Sonali" is all-confusable letters but has no digits at all.
      expect(parser.looksLikePhone('Sonali'), isFalse);
      final r = parser.parse('Sonali');
      expect(r.isValid, isFalse);
      expect(r.wasCorrected, isFalse);
    });

    test('a name beside a short number is not a phone', () {
      expect(parser.looksLikePhone('Anu 5'), isFalse);
      expect(parser.looksLikePhone('Rahul'), isFalse);
      expect(parser.looksLikePhone('Neha Gupta'), isFalse);
    });
  });

  group('rejection', () {
    test('too short to be a number', () {
      expect(parser.parse('12345').isValid, isFalse);
      expect(parser.parse('7').isValid, isFalse);
    });

    test('Indian numbers must start 6-9', () {
      expect(parser.parse('1234567890').isValid, isFalse);
      expect(parser.parse('5876543210').isValid, isFalse);
    });

    test('empty input', () {
      final r = parser.parse('   ');
      expect(r.isValid, isFalse);
      expect(r.confidence, 0);
    });

    test('invalid numbers still carry the original for user repair', () {
      final r = parser.parse('98765');
      expect(r.originalValue, '98765');
      expect(r.confidence, greaterThan(0));
    });
  });

  group('comparison key for duplicate detection (§12)', () {
    test('differently formatted forms share a key', () {
      final keys = [
        '+91 98765 43210',
        '9876543210',
        '09876543210',
        '+919876543210',
      ].map((s) => parser.parse(s).comparisonKey).toSet();
      expect(keys.length, 1);
      expect(keys.first, '9876543210');
    });

    test('different numbers do not collide', () {
      expect(
        parser.parse('9876543210').comparisonKey,
        isNot(parser.parse('9123456780').comparisonKey),
      );
    });
  });
}
