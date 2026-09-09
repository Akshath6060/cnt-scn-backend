import 'package:contact_scanner/services/contact_extraction_service.dart';
import 'package:contact_scanner/services/spatial_contact_pairing_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/ocr_fixtures.dart';

void main() {
  const extractor = ContactExtractionService();
  const pairing = SpatialContactPairingService();

  PairingOutcome run(List fragments, {double w = 800, double h = 1000}) =>
      pairing.pair(
        extractor.classify(fragments.cast()),
        documentWidth: w,
        documentHeight: h,
      );

  group('specification fixture (§29)', () {
    test('Anu + 9876543210 pair into one contact', () {
      final outcome = run(specFixture);
      expect(outcome.contacts, hasLength(1));
      expect(outcome.contacts.single.name, 'Anu');
      expect(outcome.contacts.single.parsedPhone?.nationalNumber, '9876543210');
      expect(outcome.hasLeftovers, isFalse);
    });
  });

  group('multi-row sheet', () {
    test('each name pairs with the number on its own row', () {
      final outcome = run(threeRowSheet());
      expect(outcome.contacts, hasLength(3));

      final byName = {
        for (final c in outcome.contacts) c.name: c.parsedPhone?.nationalNumber,
      };
      expect(byName['Anu'], '9876543210');
      expect(byName['Rahul'], '9123456780');
      expect(byName['Neha'], '9988776655');
      expect(outcome.hasLeftovers, isFalse);
    });

    test('contacts are returned in reading order', () {
      final outcome = run(threeRowSheet());
      expect(outcome.contacts.map((c) => c.name), ['Anu', 'Rahul', 'Neha']);
    });

    test('pairing is resolution independent (§9)', () {
      // The same layout at 4x must produce the same associations, proving the
      // row threshold is derived from the page rather than hardcoded.
      final small = run(threeRowSheet(), w: 800, h: 1000);
      final large = run(threeRowSheet(scale: 4), w: 3200, h: 4000);

      String key(PairingOutcome o) => o.contacts
          .map((c) => '${c.name}:${c.parsedPhone?.nationalNumber}')
          .join(',');

      expect(key(large), key(small));
      expect(key(small), 'Anu:9876543210,Rahul:9123456780,Neha:9988776655');
    });
  });

  group('rows that must NOT be paired', () {
    test('a name far above every number is left unmatched', () {
      final fragments = [
        ocr('Heading Sheet', x: 100, y: 20, width: 200, height: 28),
        ocr('Anu', x: 100, y: 600, width: 100, height: 30),
        ocr('9876543210', x: 350, y: 102, width: 200, height: 32),
      ];
      final outcome = run(fragments);

      // Anu sits ~500px from the only number: no contact may be invented.
      expect(
        outcome.contacts.where((c) => c.name == 'Anu' &&
            c.parsedPhone?.nationalNumber == '9876543210'),
        isEmpty,
      );
    });

    test('a lone name is reported as unmatched, not discarded (§9)', () {
      final fragments = [
        ocr('Anu', x: 100, y: 100, width: 100, height: 30),
        ocr('9876543210', x: 350, y: 102, width: 200, height: 32),
        ocr('Kiran', x: 100, y: 900, width: 110, height: 30),
      ];
      final outcome = run(fragments);
      expect(outcome.contacts, hasLength(1));
      expect(outcome.unmatchedNames.map((c) => c.text), contains('Kiran'));
    });

    test('a lone phone number is reported as unmatched', () {
      final fragments = [
        ocr('Anu', x: 100, y: 100, width: 100, height: 30),
        ocr('9876543210', x: 350, y: 102, width: 200, height: 32),
        ocr('9000011111', x: 350, y: 900, width: 200, height: 32),
      ];
      final outcome = run(fragments);
      expect(outcome.contacts, hasLength(1));
      expect(outcome.unmatchedPhones, hasLength(1));
    });

    test('two names on one row do not both claim the same number', () {
      final fragments = [
        ocr('Anu', x: 100, y: 100, width: 80, height: 30),
        ocr('Rahul', x: 200, y: 100, width: 80, height: 30),
        ocr('9876543210', x: 400, y: 102, width: 200, height: 32),
      ];
      final outcome = run(fragments);
      expect(outcome.contacts, hasLength(1));
      expect(outcome.unmatchedNames, hasLength(1));
    });
  });

  group('row metrics', () {
    test('threshold scales with the page', () {
      final small = pairing.computeRowMetrics(
        const ContactExtractionService().classify(threeRowSheet()),
        documentWidth: 800,
        documentHeight: 1000,
      );
      final large = pairing.computeRowMetrics(
        const ContactExtractionService().classify(threeRowSheet(scale: 4)),
        documentWidth: 3200,
        documentHeight: 4000,
      );
      expect(large.rowThreshold, greaterThan(small.rowThreshold * 3));
      expect(large.medianTextHeight, closeTo(small.medianTextHeight * 4, 1));
    });
  });
}
