import 'package:contact_scanner/models/expiry_option.dart';
import 'package:contact_scanner/models/extracted_contact.dart';
import 'package:contact_scanner/platform/native_contacts/native_contacts_gateway.dart';
import 'package:contact_scanner/services/duplicate_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';

ExtractedContact contact(String name, String phone, {String id = 'c1'}) =>
    ExtractedContact(id: id, name: name, phone: phone, confidence: 0.9);

NativeContact existing(String name, List<String> phones, {String id = 'OS_1'}) =>
    NativeContact(id: id, displayName: name, phones: phones);

void main() {
  const detector = DuplicateDetectionService();

  group('duplicate detection (§12)', () {
    test('exact phone match', () {
      final matches = detector.findDuplicates(
        [contact('Anu', '+919876543210')],
        [existing('Anu', ['+919876543210'])],
      );
      expect(matches, hasLength(1));
      expect(matches.single.matchType, DuplicateMatchType.exactPhone);
    });

    test('normalised match across separators', () {
      final matches = detector.findDuplicates(
        [contact('Anu', '+919876543210')],
        [existing('Anu S', ['+91 98765 43210'])],
      );
      expect(matches, hasLength(1));
      expect(matches.single.matchType, DuplicateMatchType.normalizedPhone);
    });

    test('same number written with a different country-code form', () {
      final matches = detector.findDuplicates(
        [contact('Anu', '+919876543210')],
        [existing('Anu', ['09876543210'])],
      );
      expect(matches, hasLength(1));
      expect(matches.single.matchType, DuplicateMatchType.countryCodeVariant);
    });

    test('bare national number matches a stored international one', () {
      final matches = detector.findDuplicates(
        [contact('Anu', '9876543210')],
        [existing('Anu', ['+91 9876543210'])],
      );
      expect(matches, hasLength(1));
    });

    test('different numbers are not duplicates', () {
      final matches = detector.findDuplicates(
        [contact('Anu', '9876543210')],
        [existing('Rahul', ['9123456780'])],
      );
      expect(matches, isEmpty);
    });

    test('an empty phonebook yields no matches', () {
      expect(
        detector.findDuplicates([contact('Anu', '9876543210')], const []),
        isEmpty,
      );
    });

    test('the default resolution is Skip (§12)', () {
      final matches = detector.findDuplicates(
        [contact('Anu', '9876543210')],
        [existing('Anu', ['9876543210'])],
      );
      expect(matches.single.resolution, DuplicateResolution.skip);
    });

    test('matches only the first hit per contact', () {
      final matches = detector.findDuplicates(
        [contact('Anu', '9876543210')],
        [
          existing('Anu Home', ['9876543210'], id: 'OS_1'),
          existing('Anu Work', ['9876543210'], id: 'OS_2'),
        ],
      );
      expect(matches, hasLength(1));
    });
  });

  group('expiry calculation (§11)', () {
    final now = DateTime(2026, 9, 9, 12, 0);

    test('preset durations resolve correctly', () {
      expect(ExpiryOption.oneHour.resolve(now), DateTime(2026, 9, 9, 13, 0));
      expect(ExpiryOption.sixHours.resolve(now), DateTime(2026, 9, 9, 18, 0));
      expect(ExpiryOption.twelveHours.resolve(now), DateTime(2026, 9, 10, 0, 0));
      expect(ExpiryOption.oneDay.resolve(now), DateTime(2026, 9, 10, 12, 0));
      expect(ExpiryOption.threeDays.resolve(now), DateTime(2026, 9, 12, 12, 0));
      expect(ExpiryOption.sevenDays.resolve(now), DateTime(2026, 9, 16, 12, 0));
    });

    test('Never means permanent and resolves to null', () {
      expect(ExpiryOption.never.isPermanent, isTrue);
      expect(ExpiryOption.never.resolve(now), isNull);
      expect(const ExpirySelection.permanent().isTemporary, isFalse);
    });

    test('custom expiry uses the supplied instant', () {
      final custom = DateTime(2026, 12, 25, 9, 30);
      final selection =
          ExpirySelection(option: ExpiryOption.custom, customValue: custom);
      expect(selection.resolve(now), custom);
      expect(selection.isTemporary, isTrue);
    });

    test('a past custom value is rejected (§11)', () {
      final past = now.subtract(const Duration(hours: 1));
      final selection =
          ExpirySelection(option: ExpiryOption.custom, customValue: past);
      expect(selection.isInvalidAt(now), isTrue);
    });

    test('a missing custom value is rejected', () {
      const selection = ExpirySelection(option: ExpiryOption.custom);
      expect(selection.isInvalidAt(now), isTrue);
    });

    test('a future custom value is accepted', () {
      final future = now.add(const Duration(days: 2));
      final selection =
          ExpirySelection(option: ExpiryOption.custom, customValue: future);
      expect(selection.isInvalidAt(now), isFalse);
    });

    test('presets are never considered invalid', () {
      for (final option in ExpiryOption.values) {
        if (option == ExpiryOption.custom) continue;
        expect(
          ExpirySelection(option: option).isInvalidAt(now),
          isFalse,
          reason: option.name,
        );
      }
    });

    test('all six presets from the specification exist', () {
      final labels = ExpiryOption.values.map((o) => o.label).toList();
      expect(
        labels,
        containsAll([
          '1 Hour', '6 Hours', '12 Hours', '24 Hours',
          '3 Days', '7 Days', 'Custom Date & Time', 'Never',
        ]),
      );
    });
  });
}
