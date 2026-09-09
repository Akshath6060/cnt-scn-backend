import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../imaging/gray_image.dart';
import '../imaging/kernels/contours.dart';
import '../imaging/kernels/morphology.dart';
import '../imaging/kernels/threshold.dart';
import '../models/recognized_text.dart';

/// Stage 3.1 — locates handwritten text regions (§6).
///
/// Kept separate from recognition so either half can be replaced on its own
/// (§35). Coordinates returned are always relative to the *document* image
/// passed in.
abstract class TextDetector {
  String get engineName;

  /// Detects candidate text regions in [document].
  Future<List<TextRegion>> detect(img.Image document);

  Future<void> dispose();
}

/// Default detector: connected-component analysis with directional morphology.
///
/// This is the classical approach and it suits the problem well — a contact
/// sheet is high-contrast, sparse, and organised in rows. Characters are found
/// as components, then merged horizontally into words and lines. It needs no
/// model file, so detection keeps working before the trained detector exists.
class MorphologicalTextDetector implements TextDetector {
  const MorphologicalTextDetector();

  @override
  String get engineName => 'Morphological (connected components)';

  @override
  Future<void> dispose() async {}

  @override
  Future<List<TextRegion>> detect(img.Image document) async {
    if (document.width < 16 || document.height < 16) return const [];

    // The document arrives black-on-white; flip so ink is the 255 foreground
    // that the labelling and morphology kernels expect.
    final gray = GrayImage.fromImage(document);
    var binary = Threshold.adaptiveMean(gray, offset: 10);

    // Drop single-pixel speckle before measuring character size.
    binary = Morphology.open(binary, radiusX: 1, radiusY: 1);

    // 1. Character-level components give us the page's text scale.
    final glyphs = Contours.connectedComponents(binary, minPixels: 6);
    if (glyphs.isEmpty) return const [];

    final glyphHeight = _typicalGlyphHeight(glyphs, document.height);
    if (glyphHeight <= 0) return const [];

    // 2. Merge characters into words/lines.
    //    The horizontal radius spans inter-character gaps but not the wide
    //    column gap between a name and its phone number, which is what keeps
    //    the two from fusing into one region.
    final mergeX = math.max(1, (glyphHeight * 0.45).round());
    final mergeY = math.max(1, (glyphHeight * 0.10).round());
    final merged = Morphology.close(binary, radiusX: mergeX, radiusY: mergeY);

    // 3. Regions are the merged components, filtered for text plausibility.
    final minPixels = math.max(12, (glyphHeight * glyphHeight * 0.10).round());
    final components = Contours.connectedComponents(merged, minPixels: minPixels);

    final regions = <TextRegion>[];
    for (final c in components) {
      final confidence = _scoreAsText(c, glyphHeight, document);
      if (confidence <= 0) continue;

      // Pad slightly: closing erodes a pixel or two off the extremes, and the
      // recogniser benefits from a little whitespace around the strokes.
      final padX = math.max(2.0, glyphHeight * 0.15);
      final padY = math.max(2.0, glyphHeight * 0.20);

      regions.add(
        TextRegion(
          boundingBox: c.box.inflate(
            padX,
            padY,
            maxWidth: document.width.toDouble(),
            maxHeight: document.height.toDouble(),
          ),
          confidence: confidence,
        ),
      );
    }

    // Reading order: top to bottom, then left to right within a row.
    final rowTolerance = glyphHeight * 0.6;
    regions.sort((a, b) {
      final dy = a.boundingBox.centerY - b.boundingBox.centerY;
      if (dy.abs() > rowTolerance) return dy.compareTo(0);
      return a.boundingBox.left.compareTo(b.boundingBox.left);
    });

    return regions;
  }

  /// Median height of plausibly character-sized components.
  ///
  /// The median resists both dust specks and a long rule line, either of which
  /// would wreck a mean.
  double _typicalGlyphHeight(List<ConnectedComponent> glyphs, int documentHeight) {
    final heights = glyphs
        .map((g) => g.box.height)
        // Ignore anything taller than a fifth of the page: that is a border or
        // a fold shadow, not a character.
        .where((h) => h >= 3 && h <= documentHeight * 0.2)
        .toList()
      ..sort();
    if (heights.isEmpty) return 0;
    return heights[heights.length ~/ 2];
  }

  /// Text-likeness score in [0, 1]; 0 rejects the region.
  double _scoreAsText(
    ConnectedComponent c,
    double glyphHeight,
    img.Image document,
  ) {
    final box = c.box;

    // Reject regions far outside the page's own text scale.
    if (box.height < glyphHeight * 0.4) return 0;
    if (box.height > glyphHeight * 6) return 0;

    // Reject full-width rules and page borders.
    if (box.width > document.width * 0.97) return 0;
    if (box.height > document.height * 0.5) return 0;

    // A text region is wider than it is tall, or at least not a thin spike.
    final aspect = box.width / math.max(box.height, 1);
    if (aspect < 0.25) return 0;

    var score = 0.55;

    // Handwritten words typically run 1.5x–20x wider than tall.
    if (aspect >= 1.0 && aspect <= 20) score += 0.20;

    // Fill ratio: text is neither sparse dust nor a solid block.
    final fill = c.fillRatio;
    if (fill > 0.06 && fill < 0.85) {
      score += 0.15;
    } else if (fill >= 0.85) {
      // A nearly solid rectangle is a filled box or a shadow, not writing.
      score -= 0.30;
    }

    // Height close to the page's typical glyph height is a strong signal.
    final heightRatio = box.height / glyphHeight;
    if (heightRatio >= 0.7 && heightRatio <= 2.5) score += 0.10;

    return score.clamp(0.0, 0.99);
  }
}

/// Stage 3.1 backed by a bundled `text_detector.tflite`.
///
/// Deliberately a thin shell: the trained detector does not exist yet, so this
/// class documents the contract and fails over to [MorphologicalTextDetector]
/// rather than pretending to work. Replace [_runModel] when the model lands —
/// nothing outside this file needs to change (§6 "the model can later be
/// replaced without rewriting the whole application").
class TfliteTextDetector implements TextDetector {
  TfliteTextDetector({required this.fallback});

  /// Used whenever the model is absent or inference fails.
  final TextDetector fallback;

  @override
  String get engineName => 'TFLite text detector';

  @override
  Future<List<TextRegion>> detect(img.Image document) => fallback.detect(document);

  @override
  Future<void> dispose() => fallback.dispose();
}

/// Utility shared by detector implementations.
extension TextRegionListX on List<TextRegion> {
  /// Removes regions almost entirely contained in a larger neighbour, which a
  /// detector can emit when a word is found both alone and as part of a line.
  List<TextRegion> deduplicated({double overlapThreshold = 0.85}) {
    final sorted = [...this]
      ..sort((a, b) => b.boundingBox.area.compareTo(a.boundingBox.area));
    final kept = <TextRegion>[];

    for (final region in sorted) {
      final isContained = kept.any((k) {
        final b = region.boundingBox, o = k.boundingBox;
        final ix = math.max(0.0, math.min(b.right, o.right) - math.max(b.left, o.left));
        final iy = math.max(0.0, math.min(b.bottom, o.bottom) - math.max(b.top, o.top));
        final intersection = ix * iy;
        return b.area > 0 && intersection / b.area >= overlapThreshold;
      });
      if (!isContained) kept.add(region);
    }
    return kept;
  }
}
