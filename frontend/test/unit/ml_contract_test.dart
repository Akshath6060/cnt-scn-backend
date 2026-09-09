import 'dart:typed_data';

import 'package:contact_scanner/core/constants/app_constants.dart';
import 'package:contact_scanner/ml/charset.dart';
import 'package:contact_scanner/ml/ctc_decoder.dart';
import 'package:contact_scanner/ml/handwriting_recognizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../fixtures/text_region_helper.dart';

/// One-hot logit row for [index], with a configurable peak.
List<double> oneHot(int index, int classes, {double peak = 12.0}) {
  final row = List<double>.filled(classes, 0.0);
  row[index] = peak;
  return row;
}

void main() {
  const charset = Charset.fallback;
  const decoder = CtcDecoder(charset);
  final classes = charset.length;

  group('charset matches the training vocabulary', () {
    test('has 81 classes with blank at index 0', () {
      expect(charset.length, 81);
      expect(charset.blankIndex, 0);
      // Index 0 is the CTC blank and decodes to nothing.
      expect(charset[0], '');
    });

    test('digit indices map as the backend defines them', () {
      // CHARS = "-0123456789abc..." so '0' is index 1 .. '9' is index 10.
      for (var d = 0; d <= 9; d++) {
        expect(charset[1 + d], '$d');
      }
      expect(charset[11], 'a');
      expect(charset[37], 'A');
    });
  });

  group('greedy CTC decoding (§31)', () {
    test('collapses repeats and drops blanks', () {
      // "9" repeated, blank, "8" -> "98"
      const nine = 10; // '9'
      const eight = 9; // '8'
      final logits = [
        oneHot(nine, classes),
        oneHot(nine, classes),
        oneHot(0, classes), // blank
        oneHot(nine, classes),
        oneHot(eight, classes),
      ];
      // repeat-collapse gives 9, then blank resets, then 9, then 8 -> "998"
      expect(decoder.decode(logits).text, '998');
    });

    test('decodes a full phone number', () {
      const digits = '9876543210';
      final logits = <List<double>>[];
      for (final ch in digits.split('')) {
        final index = charset.characters.indexOf(ch);
        logits.add(oneHot(index, classes));
        logits.add(oneHot(0, classes)); // blank between characters
      }
      expect(decoder.decode(logits).text, digits);
    });

    test('a blank-only sequence decodes to empty with zero confidence', () {
      final logits = List.generate(20, (_) => oneHot(0, classes));
      final result = decoder.decode(logits);
      expect(result.text, isEmpty);
      expect(result.confidence, 0);
    });

    test('confidence reflects logit peakiness', () {
      final confident = [oneHot(10, classes, peak: 20)];
      final unsure = [oneHot(10, classes, peak: 0.2)];
      expect(decoder.decode(confident).confidence,
          greaterThan(decoder.decode(unsure).confidence));
      expect(decoder.decode(confident).confidence, lessThanOrEqualTo(1.0));
    });

    test('empty and malformed input does not throw', () {
      expect(decoder.decode(const []).text, isEmpty);
      expect(decoder.decode([const []]).text, isEmpty);
    });

    test('out-of-range class indices are ignored rather than crashing', () {
      // A model emitting more classes than the charset knows about.
      final row = List<double>.filled(classes + 5, 0.0);
      row[classes + 2] = 9.0;
      expect(decoder.decode([row]).text, isEmpty);
    });
  });

  group('input tensor contract (§31)', () {
    test('produces exactly 1x3x32x800 float32 values', () {
      final crop = img.Image(width: 120, height: 40);
      img.fill(crop, color: img.ColorRgb8(0, 0, 0));

      final tensor = TFLiteHandwritingRecognizer.buildInputTensor(crop);
      expect(tensor, isA<Float32List>());
      expect(
        tensor.length,
        AppConstants.recognizerInputChannels *
            AppConstants.recognizerInputHeight *
            AppConstants.recognizerInputWidth,
      );
      expect(tensor.length, 3 * 32 * 800);
    });

    test('normalises to [-1, 1] using value / 127.5 - 1', () {
      final black = img.Image(width: 32, height: 32);
      img.fill(black, color: img.ColorRgb8(0, 0, 0));
      final t = TFLiteHandwritingRecognizer.buildInputTensor(black);
      // Top-left pixel of the R plane is black -> -1.0
      expect(t[0], closeTo(-1.0, 1e-6));

      final white = img.Image(width: 32, height: 32);
      img.fill(white, color: img.ColorRgb8(255, 255, 255));
      final tw = TFLiteHandwritingRecognizer.buildInputTensor(white);
      expect(tw[0], closeTo(1.0, 1e-6));
    });

    test('pads to the right with white, matching the training canvas', () {
      final narrow = img.Image(width: 16, height: 32);
      img.fill(narrow, color: img.ColorRgb8(0, 0, 0));
      final t = TFLiteHandwritingRecognizer.buildInputTensor(narrow);

      // Row 0 of the R plane: image occupies the left, padding the right.
      expect(t[0], closeTo(-1.0, 1e-6)); // inside the crop
      expect(t[799], closeTo(1.0, 1e-6)); // far right padding is white
    });

    test('is laid out NCHW: planes are contiguous per channel', () {
      // A pure red crop: R plane = 1.0, G and B planes = -1.0.
      final red = img.Image(width: 800, height: 32);
      img.fill(red, color: img.ColorRgb8(255, 0, 0));
      final t = TFLiteHandwritingRecognizer.buildInputTensor(red);

      const plane = 32 * 800;
      expect(t[0], closeTo(1.0, 1e-6)); // R
      expect(t[plane], closeTo(-1.0, 1e-6)); // G
      expect(t[plane * 2], closeTo(-1.0, 1e-6)); // B
    });

    test('a very wide crop is capped at 800 px rather than overflowing', () {
      final wide = img.Image(width: 4000, height: 32);
      img.fill(wide, color: img.ColorRgb8(10, 10, 10));
      final t = TFLiteHandwritingRecognizer.buildInputTensor(wide);
      expect(t.length, 3 * 32 * 800);
    });
  });

  group('mock recogniser (§30)', () {
    test('is explicitly flagged as a mock', () {
      expect(MockHandwritingRecognizer().isMock, isTrue);
    });

    test('is deterministic for a given seed', () async {
      final doc = img.Image(width: 800, height: 400);
      final regions = [
        for (var i = 0; i < 4; i++)
          TextRegionForTest.make(x: i.isEven ? 50 : 500, y: 60.0 * i),
      ];
      final a = await MockHandwritingRecognizer(seed: 3).recognize(doc, regions);
      final b = await MockHandwritingRecognizer(seed: 3).recognize(doc, regions);
      expect(a.map((r) => r.text).toList(), b.map((r) => r.text).toList());
    });
  });
}
