import '../gray_image.dart';

/// Binary morphology on 0/255 images, with 255 as foreground.
///
/// Implemented as two 1-D passes over a rectangular structuring element,
/// which is separable for dilation and erosion alike.
class Morphology {
  const Morphology._();

  static GrayImage dilate(GrayImage src, {int radiusX = 1, int radiusY = 1}) =>
      _apply(src, radiusX, radiusY, isDilate: true);

  static GrayImage erode(GrayImage src, {int radiusX = 1, int radiusY = 1}) =>
      _apply(src, radiusX, radiusY, isDilate: false);

  /// Erode then dilate — removes isolated speckle without growing strokes.
  static GrayImage open(GrayImage src, {int radiusX = 1, int radiusY = 1}) =>
      dilate(erode(src, radiusX: radiusX, radiusY: radiusY),
          radiusX: radiusX, radiusY: radiusY);

  /// Dilate then erode — closes small gaps inside a stroke, which is what
  /// reconnects a pen skip in the middle of a digit.
  static GrayImage close(GrayImage src, {int radiusX = 1, int radiusY = 1}) =>
      erode(dilate(src, radiusX: radiusX, radiusY: radiusY),
          radiusX: radiusX, radiusY: radiusY);

  static GrayImage _apply(
    GrayImage src,
    int radiusX,
    int radiusY, {
    required bool isDilate,
  }) {
    if (radiusX <= 0 && radiusY <= 0) return src.clone();

    GrayImage current = src;

    if (radiusX > 0) {
      final tmp = current.emptyLike();
      for (var y = 0; y < current.height; y++) {
        for (var x = 0; x < current.width; x++) {
          var value = isDilate ? 0 : 255;
          for (var k = -radiusX; k <= radiusX; k++) {
            final v = current.clamped(x + k, y);
            value = isDilate ? (v > value ? v : value) : (v < value ? v : value);
          }
          tmp.data[y * current.width + x] = value;
        }
      }
      current = tmp;
    }

    if (radiusY > 0) {
      final tmp = current.emptyLike();
      for (var y = 0; y < current.height; y++) {
        for (var x = 0; x < current.width; x++) {
          var value = isDilate ? 0 : 255;
          for (var k = -radiusY; k <= radiusY; k++) {
            final v = current.clamped(x, y + k);
            value = isDilate ? (v > value ? v : value) : (v < value ? v : value);
          }
          tmp.data[y * current.width + x] = value;
        }
      }
      current = tmp;
    }

    return identical(current, src) ? src.clone() : current;
  }
}
