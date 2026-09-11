import 'package:contact_scanner/models/entity_type.dart';
import 'package:contact_scanner/services/contact_extraction_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/ocr_fixtures.dart';

void main() {
  const extractor = ContactExtractionService();

  EntityType classifyOne(String text, {double confidence = 0.9}) {
    final result = extractor.classify([
      ocr(text, x: 100, y: 100, width: 150, height: 30, confidence: confidence),
    ]);
    return result.single.entityType;
  }

  group('entity classification (§8.1)', () {
    test('phone numbers', () {
      expect(classifyOne('9876543210'), EntityType.phone);
      expect(classifyOne('+91 98765 43210'), EntityType.phone);
      expect(classifyOne('(98765) 43210'), EntityType.phone);
    });

    test('keeps a number visible when OCR misreads unsupported characters', () {
      final result = extractor.classify([
        ocr('98u65x3210', x: 100, y: 100, width: 180, height: 30),
      ]).single;

      expect(result.entityType, EntityType.phone);
      expect(result.phone?.isValid, isFalse);
      expect(result.text, '98u65x3210');
    });

    test('does not mistake ordinary alphanumeric text for a phone', () {
      expect(classifyOne('Room 12345'), isNot(EntityType.phone));
    });

    test('names', () {
      expect(classifyOne('Anu'), EntityType.name);
      expect(classifyOne('Rahul Sharma'), EntityType.name);
      expect(classifyOne('Neha'), EntityType.name);
    });

    test('emails are recognised and ignored (§8.5)', () {
      expect(classifyOne('anu@example.com'), EntityType.email);
      expect(EntityType.email.isIgnorable, isTrue);
      expect(EntityType.email.isContactField, isFalse);
    });

    test('addresses', () {
      expect(classifyOne('12 Park Road'), EntityType.address);
      expect(classifyOne('Near Gandhi Nagar'), EntityType.address);
    });

    test('organisations', () {
      expect(classifyOne('St Xavier College'), EntityType.organization);
      expect(classifyOne('Acme Pvt Ltd'), EntityType.organization);
    });

    test('column headings', () {
      expect(classifyOne('Name'), EntityType.heading);
      expect(classifyOne('Phone'), EntityType.heading);
      expect(classifyOne('Mobile Number'), EntityType.heading);
    });

    test('serial and page numbers', () {
      expect(classifyOne('1.'), EntityType.serialNumber);
      expect(classifyOne('12'), EntityType.serialNumber);
      expect(classifyOne('Page 3'), EntityType.serialNumber);
    });
  });

  group('nothing is discarded before pairing (§8.5)', () {
    test('ignorable entities are still returned with their positions', () {
      final fragments = [
        ocr('Name', x: 100, y: 40, width: 80, height: 24),
        ocr('Phone', x: 350, y: 40, width: 90, height: 24),
        ocr('Anu', x: 100, y: 100, width: 100, height: 30),
        ocr('9876543210', x: 350, y: 102, width: 200, height: 32),
        ocr('anu@example.com', x: 600, y: 101, width: 220, height: 30),
      ];
      final result = extractor.classify(fragments);

      // Every input fragment survives classification.
      expect(result, hasLength(5));
      // And the ignorable ones keep their geometry for row analysis.
      final email = result.firstWhere((c) => c.entityType == EntityType.email);
      expect(email.box.centerY, closeTo(116, 1));
    });
  });

  group('list markers are stripped (§8.5)', () {
    test('a leading serial does not stop a name being found', () {
      final result = extractor.classify([
        ocr('1. Anu', x: 100, y: 100, width: 140, height: 30),
      ]);
      expect(result.single.entityType, EntityType.name);
      expect(result.single.text, 'Anu');
    });
  });

  group('name scoring (§8.4)', () {
    test('rejects digit-heavy strings', () {
      expect(extractor.scoreAsName('12345', 0.9), 0);
      expect(extractor.scoreAsName('A1234', 0.9), 0);
    });

    test('rejects empty and over-long strings', () {
      expect(extractor.scoreAsName('', 0.9), 0);
      expect(extractor.scoreAsName('x' * 60, 0.9), 0);
    });

    test('rewards a typical capitalised name', () {
      final good = extractor.scoreAsName('Anu', 0.95);
      final poor = extractor.scoreAsName('xq', 0.30);
      expect(good, greaterThan(poor));
      expect(good, greaterThan(0.6));
    });

    test('recognition confidence feeds the score', () {
      expect(
        extractor.scoreAsName('Rahul', 0.95),
        greaterThan(extractor.scoreAsName('Rahul', 0.35)),
      );
    });

    test('ALL CAPS long strings score below title case', () {
      expect(
        extractor.scoreAsName('SIGNATURE', 0.9),
        lessThan(extractor.scoreAsName('Signature', 0.9)),
      );
    });
  });

  group('row context refinement (§8.4)', () {
    test('an unclassified fragment on a phone row is promoted to a name', () {
      final result = extractor.classify([
        // "Xy" alone is a weak name candidate.
        ocr('Kd', x: 100, y: 100, width: 60, height: 30, confidence: 0.55),
        ocr('9876543210', x: 350, y: 102, width: 200, height: 32),
      ]);
      final first = result.first;
      expect(first.entityType, EntityType.name);
    });

    test('names sharing a row with a number gain confidence', () {
      final withPhone = extractor.classify([
        ocr('Anu', x: 100, y: 100, width: 100, height: 30),
        ocr('9876543210', x: 350, y: 102, width: 200, height: 32),
      ]).first;

      final alone = extractor.classify([
        ocr('Anu', x: 100, y: 100, width: 100, height: 30),
      ]).first;

      expect(
        withPhone.classificationConfidence,
        greaterThan(alone.classificationConfidence),
      );
    });
  });
}
