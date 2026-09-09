import 'package:contact_scanner/models/bounding_box.dart';
import 'package:contact_scanner/models/recognized_text.dart';

/// Builds a [RecognizedText] from the synthetic-OCR shape used in §29.
RecognizedText ocr(
  String text, {
  required double x,
  required double y,
  required double width,
  required double height,
  double confidence = 0.92,
}) =>
    RecognizedText(
      text: text,
      confidence: confidence,
      boundingBox:
          BoundingBox(x: x, y: y, width: width, height: height),
    );

/// The exact fixture from the specification.
List<RecognizedText> get specFixture => [
      ocr('Anu', x: 100, y: 100, width: 100, height: 30),
      ocr('9876543210', x: 350, y: 102, width: 200, height: 32),
    ];

/// A three-row sheet, scaled by [scale] to prove resolution independence.
List<RecognizedText> threeRowSheet({double scale = 1.0}) => [
      ocr('Anu', x: 100 * scale, y: 100 * scale, width: 100 * scale, height: 30 * scale),
      ocr('9876543210', x: 350 * scale, y: 102 * scale, width: 200 * scale, height: 32 * scale),
      ocr('Rahul', x: 100 * scale, y: 170 * scale, width: 120 * scale, height: 30 * scale),
      ocr('9123456780', x: 350 * scale, y: 172 * scale, width: 200 * scale, height: 32 * scale),
      ocr('Neha', x: 100 * scale, y: 240 * scale, width: 110 * scale, height: 30 * scale),
      ocr('9988776655', x: 350 * scale, y: 241 * scale, width: 200 * scale, height: 32 * scale),
    ];
