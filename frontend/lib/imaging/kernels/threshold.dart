import 'dart:math' as math;
import 'dart:typed_data';

import '../gray_image.dart';

/// Binarisation kernels (§5).
///
/// Output convention: **255 = ink (foreground)**, 0 = paper. Working with ink
/// as the high value keeps the morphology kernels intuitive (dilation thickens
/// strokes) and matches how connected-component labelling expects its input.
class Threshold {
  const Threshold._();

  /// Bradley–Roth adaptive mean threshold via a summed-area table.
  ///
  /// O(w*h) regardless of window size, which is what makes a large window —
  /// necessary to keep whole handwritten strokes on the same side of the
  /// threshold — affordable on-device.
  ///
  /// [windowSize] is the side length of the local neighbourhood (forced odd);
  /// [offset] is subtracted from the local mean, so a larger value keeps more
  /// faint ink (§5 "faint handwriting must remain visible").
  static GrayImage adaptiveMean(
    GrayImage src, {
    int? windowSize,
    int offset = 10,
  }) {
    final w = src.width, h = src.height;
    if (w == 0 || h == 0) return src.clone();

    // Default window ≈ 1/16 of the short edge: comfortably larger than a
    // stroke, comfortably smaller than a lighting gradient. The floor of 15
    // matters — a window only a few pixels wide sits *inside* a stroke, so the
    // local mean tracks the ink itself and the stroke thresholds away.
    var window = windowSize ?? math.max(15, (w < h ? w : h) ~/ 16);
    if (window < 3) window = 3;
    if (window.isEven) window += 1;
    final radius = window ~/ 2;

    final integral = _integralImage(src);
    final dst = src.emptyLike();

    for (var y = 0; y < h; y++) {
      final y0 = (y - radius).clamp(0, h - 1);
      final y1 = (y + radius).clamp(0, h - 1);
      for (var x = 0; x < w; x++) {
        final x0 = (x - radius).clamp(0, w - 1);
        final x1 = (x + radius).clamp(0, w - 1);

        final count = (x1 - x0 + 1) * (y1 - y0 + 1);
        final sum = _rectSum(integral, w, x0, y0, x1, y1);
        final mean = sum / count;

        // Ink is darker than the local paper mean.
        dst.data[y * w + x] = src.data[y * w + x] < (mean - offset) ? 255 : 0;
      }
    }
    return dst;
  }

  /// Global Otsu threshold. Used for document-edge work where a single
  /// paper/background split is the right model.
  static GrayImage otsu(GrayImage src, {bool inkIsDark = true}) {
    final level = otsuLevel(src);
    final dst = src.emptyLike();
    for (var i = 0; i < src.length; i++) {
      final isInk = inkIsDark ? src.data[i] < level : src.data[i] >= level;
      dst.data[i] = isInk ? 255 : 0;
    }
    return dst;
  }

  /// Computes the Otsu threshold level by maximising between-class variance.
  static int otsuLevel(GrayImage src) {
    final histogram = Int32List(256);
    for (var i = 0; i < src.length; i++) {
      histogram[src.data[i]]++;
    }
    final total = src.length;
    if (total == 0) return 128;

    var sumAll = 0.0;
    for (var t = 0; t < 256; t++) {
      sumAll += t * histogram[t];
    }

    var sumBackground = 0.0;
    var weightBackground = 0;
    var best = 0.0;

    // A strongly bimodal image leaves an empty range between the two peaks, and
    // every level in that range yields the same between-class variance. Taking
    // the first maximum would put the threshold flush against the dark peak, so
    // the plateau is tracked and its midpoint returned instead.
    var plateauStart = 128;
    var plateauEnd = 128;

    for (var t = 0; t < 256; t++) {
      weightBackground += histogram[t];
      if (weightBackground == 0) continue;
      final weightForeground = total - weightBackground;
      if (weightForeground == 0) break;

      sumBackground += t * histogram[t];
      final meanBackground = sumBackground / weightBackground;
      final meanForeground = (sumAll - sumBackground) / weightForeground;
      final delta = meanBackground - meanForeground;
      final variance = weightBackground * weightForeground * delta * delta;

      if (variance > best) {
        best = variance;
        plateauStart = t;
        plateauEnd = t;
      } else if (variance == best) {
        plateauEnd = t;
      }
    }
    return (plateauStart + plateauEnd) ~/ 2;
  }

  /// Summed-area table in 64-bit so a large page cannot overflow.
  static Int64List _integralImage(GrayImage src) {
    final w = src.width, h = src.height;
    final integral = Int64List(w * h);
    for (var y = 0; y < h; y++) {
      var rowSum = 0;
      for (var x = 0; x < w; x++) {
        rowSum += src.data[y * w + x];
        integral[y * w + x] = rowSum + (y > 0 ? integral[(y - 1) * w + x] : 0);
      }
    }
    return integral;
  }

  static int _rectSum(Int64List integral, int w, int x0, int y0, int x1, int y1) {
    final d = integral[y1 * w + x1];
    final b = y0 > 0 ? integral[(y0 - 1) * w + x1] : 0;
    final c = x0 > 0 ? integral[y1 * w + x0 - 1] : 0;
    final a = (x0 > 0 && y0 > 0) ? integral[(y0 - 1) * w + x0 - 1] : 0;
    return d - b - c + a;
  }
}
