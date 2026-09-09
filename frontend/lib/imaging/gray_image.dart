import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A single-channel 8-bit image backed by a flat [Uint8List].
///
/// Every kernel in `imaging/kernels/` operates on this type rather than on
/// `img.Image`, because per-pixel access through the `image` package's
/// abstraction is roughly an order of magnitude slower — which matters on the
/// mid-range Android devices this app targets (§24).
class GrayImage {
  GrayImage(this.width, this.height, this.data)
      : assert(data.length == width * height, 'buffer size must be w*h');

  GrayImage.filled(this.width, this.height, [int value = 0])
      : data = Uint8List(width * height)..fillRange(0, width * height, value);

  final int width;
  final int height;
  final Uint8List data;

  int get length => data.length;

  int at(int x, int y) => data[y * width + x];

  void set(int x, int y, int value) => data[y * width + x] = value;

  /// Reads with edge clamping, so kernels never need bounds branches.
  int clamped(int x, int y) {
    final cx = x < 0 ? 0 : (x >= width ? width - 1 : x);
    final cy = y < 0 ? 0 : (y >= height ? height - 1 : y);
    return data[cy * width + cx];
  }

  GrayImage clone() => GrayImage(width, height, Uint8List.fromList(data));

  GrayImage emptyLike() => GrayImage(width, height, Uint8List(width * height));

  double get mean {
    if (data.isEmpty) return 0;
    var sum = 0;
    for (var i = 0; i < data.length; i++) {
      sum += data[i];
    }
    return sum / data.length;
  }

  /// Converts a colour image to luminance using ITU-R BT.601 weights.
  factory GrayImage.fromImage(img.Image source) {
    final out = Uint8List(source.width * source.height);
    var i = 0;
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final p = source.getPixel(x, y);
        // Integer approximation of 0.299R + 0.587G + 0.114B.
        out[i++] =
            ((p.r.toInt() * 77 + p.g.toInt() * 150 + p.b.toInt() * 29) >> 8)
                .clamp(0, 255);
      }
    }
    return GrayImage(source.width, source.height, out);
  }

  /// Materialises back into an `image` package RGB image for encoding/display.
  img.Image toImage() {
    final out = img.Image(width: width, height: height);
    var i = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final v = data[i++];
        out.setPixelRgb(x, y, v, v, v);
      }
    }
    return out;
  }
}
