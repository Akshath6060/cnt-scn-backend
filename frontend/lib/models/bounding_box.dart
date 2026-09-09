import 'dart:math' as math;

/// An axis-aligned rectangle in *document* coordinate space.
///
/// All detector output is normalised into this type. Coordinates are stored in
/// pixels relative to the flattened, perspective-corrected document image, so
/// downstream spatial reasoning never has to know about camera resolution or
/// the detection downscale factor (§24 "maintain coordinate mapping").
class BoundingBox {
  const BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  double get left => x;
  double get top => y;
  double get right => x + width;
  double get bottom => y + height;
  double get centerX => x + width / 2;
  double get centerY => y + height / 2;
  double get area => width * height;

  /// Vertical overlap with [other] as a fraction of the *smaller* box height.
  ///
  /// Using the smaller height (rather than the union) keeps a short box — a
  /// lone initial, say — from being penalised against a tall one on the
  /// same row.
  double verticalOverlapRatio(BoundingBox other) {
    final overlap = math.min(bottom, other.bottom) - math.max(top, other.top);
    if (overlap <= 0) return 0;
    final smaller = math.min(height, other.height);
    if (smaller <= 0) return 0;
    return (overlap / smaller).clamp(0.0, 1.0);
  }

  /// Horizontal gap between the two boxes; 0 when they overlap.
  double horizontalGapTo(BoundingBox other) {
    if (right <= other.left) return other.left - right;
    if (other.right <= left) return left - other.right;
    return 0;
  }

  /// Scales the box by [factor] — used to map detection-resolution
  /// coordinates back onto the full-resolution document.
  BoundingBox scaled(double factor) => BoundingBox(
        x: x * factor,
        y: y * factor,
        width: width * factor,
        height: height * factor,
      );

  /// Grows the box by [dx]/[dy] on each side, clamped to a bounding canvas.
  BoundingBox inflate(
    double dx,
    double dy, {
    double? maxWidth,
    double? maxHeight,
  }) {
    final nx = math.max(0.0, x - dx);
    final ny = math.max(0.0, y - dy);
    var nw = width + dx * 2;
    var nh = height + dy * 2;
    if (maxWidth != null) nw = math.min(nw, maxWidth - nx);
    if (maxHeight != null) nh = math.min(nh, maxHeight - ny);
    return BoundingBox(
      x: nx,
      y: ny,
      width: math.max(1.0, nw),
      height: math.max(1.0, nh),
    );
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  factory BoundingBox.fromJson(Map<String, dynamic> json) => BoundingBox(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
      );

  @override
  String toString() =>
      'BoundingBox(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)}, '
      '${width.toStringAsFixed(1)}x${height.toStringAsFixed(1)})';

  @override
  bool operator ==(Object other) =>
      other is BoundingBox &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);
}
