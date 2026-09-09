import 'dart:math' as math;
import 'dart:typed_data';

import '../gray_image.dart';

/// Linear and statistical filters (§5 preprocessing pipeline).
class Filters {
  const Filters._();

  /// Separable Gaussian blur.
  ///
  /// Two 1-D passes cost O(w*h*k) instead of O(w*h*k²); at the radii used for
  /// illumination estimation that difference is the whole frame budget.
  static GrayImage gaussianBlur(GrayImage src, {required int radius}) {
    if (radius <= 0) return src.clone();
    final kernel = _gaussianKernel(radius);
    final tmp = src.emptyLike();
    final dst = src.emptyLike();

    // Horizontal pass.
    for (var y = 0; y < src.height; y++) {
      final row = y * src.width;
      for (var x = 0; x < src.width; x++) {
        var acc = 0.0;
        for (var k = -radius; k <= radius; k++) {
          acc += kernel[k + radius] * src.clamped(x + k, y);
        }
        tmp.data[row + x] = acc.round().clamp(0, 255);
      }
    }

    // Vertical pass.
    for (var y = 0; y < src.height; y++) {
      final row = y * src.width;
      for (var x = 0; x < src.width; x++) {
        var acc = 0.0;
        for (var k = -radius; k <= radius; k++) {
          acc += kernel[k + radius] * tmp.clamped(x, y + k);
        }
        dst.data[row + x] = acc.round().clamp(0, 255);
      }
    }
    return dst;
  }

  static Float64List _gaussianKernel(int radius) {
    // Standard OpenCV relationship between radius and sigma.
    final sigma = 0.3 * (radius - 1) + 0.8;
    final kernel = Float64List(radius * 2 + 1);
    var sum = 0.0;
    for (var i = -radius; i <= radius; i++) {
      final v = math.exp(-(i * i) / (2 * sigma * sigma));
      kernel[i + radius] = v;
      sum += v;
    }
    for (var i = 0; i < kernel.length; i++) {
      kernel[i] /= sum;
    }
    return kernel;
  }

  /// 3x3 median filter — removes salt-and-pepper speckle without the stroke
  /// thinning a mean filter causes, which matters for faint handwriting (§5).
  static GrayImage median3x3(GrayImage src) {
    final dst = src.emptyLike();
    final window = List<int>.filled(9, 0);
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        var i = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            window[i++] = src.clamped(x + dx, y + dy);
          }
        }
        window.sort();
        dst.data[y * src.width + x] = window[4];
      }
    }
    return dst;
  }

  /// Flattens uneven lighting by dividing out a blurred background estimate.
  ///
  /// This is what rescues a photo with a shadow across one half of the page:
  /// the background model absorbs the gradient, leaving stroke contrast intact
  /// so that thresholding does not black out the shadowed side.
  static GrayImage correctIllumination(GrayImage src, {int? radius}) {
    // Background radius must be well above stroke width to avoid erasing text.
    final r = radius ?? math.max(8, (math.min(src.width, src.height) * 0.04).round());
    final background = gaussianBlur(src, radius: r);
    final dst = src.emptyLike();

    for (var i = 0; i < src.length; i++) {
      final bg = background.data[i];
      // Normalise each pixel against local paper brightness, rescaled to 200
      // (not 255) to leave headroom before clipping.
      final value = bg == 0 ? src.data[i] : ((src.data[i] * 200) ~/ bg);
      dst.data[i] = value.clamp(0, 255);
    }
    return dst;
  }

  /// Variance of the Laplacian — the standard focus measure (§26).
  ///
  /// A sharp page has strong second derivatives at every stroke edge; a blurred
  /// one does not.
  static double laplacianVariance(GrayImage src) {
    if (src.width < 3 || src.height < 3) return 0;
    final values = <double>[];
    var sum = 0.0;

    for (var y = 1; y < src.height - 1; y++) {
      for (var x = 1; x < src.width - 1; x++) {
        // 4-neighbour Laplacian.
        final v = (src.at(x - 1, y) +
                src.at(x + 1, y) +
                src.at(x, y - 1) +
                src.at(x, y + 1) -
                4 * src.at(x, y))
            .toDouble();
        values.add(v);
        sum += v;
      }
    }
    if (values.isEmpty) return 0;

    final mean = sum / values.length;
    var variance = 0.0;
    for (final v in values) {
      final d = v - mean;
      variance += d * d;
    }
    return variance / values.length;
  }

  /// Sobel gradient magnitude, used for document edge detection.
  static GrayImage sobelMagnitude(GrayImage src) {
    final dst = src.emptyLike();
    for (var y = 1; y < src.height - 1; y++) {
      for (var x = 1; x < src.width - 1; x++) {
        final tl = src.at(x - 1, y - 1), tc = src.at(x, y - 1), tr = src.at(x + 1, y - 1);
        final ml = src.at(x - 1, y), mr = src.at(x + 1, y);
        final bl = src.at(x - 1, y + 1), bc = src.at(x, y + 1), br = src.at(x + 1, y + 1);

        final gx = (tr + 2 * mr + br) - (tl + 2 * ml + bl);
        final gy = (bl + 2 * bc + br) - (tl + 2 * tc + tr);

        dst.data[y * src.width + x] =
            math.sqrt((gx * gx + gy * gy).toDouble()).round().clamp(0, 255);
      }
    }
    return dst;
  }

  /// Nearest-neighbour-free bilinear downscale.
  static GrayImage resize(GrayImage src, int width, int height) {
    if (width == src.width && height == src.height) return src.clone();
    final dst = GrayImage(width, height, Uint8List(width * height));
    final xRatio = src.width / width;
    final yRatio = src.height / height;

    for (var y = 0; y < height; y++) {
      final sy = (y + 0.5) * yRatio - 0.5;
      final y0 = sy.floor();
      final fy = sy - y0;
      for (var x = 0; x < width; x++) {
        final sx = (x + 0.5) * xRatio - 0.5;
        final x0 = sx.floor();
        final fx = sx - x0;

        final p00 = src.clamped(x0, y0).toDouble();
        final p10 = src.clamped(x0 + 1, y0).toDouble();
        final p01 = src.clamped(x0, y0 + 1).toDouble();
        final p11 = src.clamped(x0 + 1, y0 + 1).toDouble();

        final top = p00 + (p10 - p00) * fx;
        final bottom = p01 + (p11 - p01) * fx;
        dst.data[y * width + x] =
            (top + (bottom - top) * fy).round().clamp(0, 255);
      }
    }
    return dst;
  }
}
