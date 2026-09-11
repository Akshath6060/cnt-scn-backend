import 'package:contact_scanner/ml/text_detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test(
    'merges handwritten glyphs into fields despite small camera noise',
    () async {
      final page = img.Image(width: 320, height: 140);
      img.fill(page, color: img.ColorRgb8(255, 255, 255));

      // Two fields on one row, built from separated character-like strokes.
      for (final startX in [24, 190]) {
        for (var i = 0; i < 7; i++) {
          final x = startX + i * 10;
          img.fillRect(
            page,
            x1: x,
            y1: 72,
            x2: x + 5,
            y2: 93,
            color: img.ColorRgb8(20, 20, 20),
          );
        }
      }

      // Enough tiny components to skew a simple median height estimate.
      for (var i = 0; i < 20; i++) {
        final x = 4 + i * 15;
        img.fillRect(
          page,
          x1: x,
          y1: 12,
          x2: x + 2,
          y2: 14,
          color: img.ColorRgb8(30, 30, 30),
        );
      }

      final regions = await const MorphologicalTextDetector().detect(page);

      expect(regions, hasLength(2));
      expect(regions.first.boundingBox.centerX, lessThan(150));
      expect(regions.last.boundingBox.centerX, greaterThan(150));
    },
  );
}
