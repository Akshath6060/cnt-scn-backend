import 'dart:typed_data';

import 'quality_report.dart';

/// A quadrilateral in image coordinates, ordered clockwise from top-left.
class DocumentCorners {
  const DocumentCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// The full frame, used when detection fails and the user proceeds anyway.
  factory DocumentCorners.fullFrame(int width, int height) => DocumentCorners(
        topLeft: const Point(0, 0),
        topRight: Point(width.toDouble(), 0),
        bottomRight: Point(width.toDouble(), height.toDouble()),
        bottomLeft: Point(0, height.toDouble()),
      );

  final Point topLeft;
  final Point topRight;
  final Point bottomRight;
  final Point bottomLeft;

  List<Point> get points => [topLeft, topRight, bottomRight, bottomLeft];

  /// Shoelace area of the quadrilateral.
  double get area {
    final p = points;
    var sum = 0.0;
    for (var i = 0; i < p.length; i++) {
      final a = p[i];
      final b = p[(i + 1) % p.length];
      sum += a.x * b.y - b.x * a.y;
    }
    return sum.abs() / 2;
  }

  DocumentCorners scaled(double factor) => DocumentCorners(
        topLeft: topLeft.scaled(factor),
        topRight: topRight.scaled(factor),
        bottomRight: bottomRight.scaled(factor),
        bottomLeft: bottomLeft.scaled(factor),
      );

  DocumentCorners replace(int index, Point value) {
    final p = List<Point>.from(points)..[index] = value;
    return DocumentCorners(
      topLeft: p[0],
      topRight: p[1],
      bottomRight: p[2],
      bottomLeft: p[3],
    );
  }
}

/// Immutable 2-D point.
class Point {
  const Point(this.x, this.y);
  final double x;
  final double y;

  Point scaled(double f) => Point(x * f, y * f);
  Point clampTo(double w, double h) =>
      Point(x.clamp(0.0, w), y.clamp(0.0, h));

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// The flattened, top-down document produced by Phase 1 (§4).
class AlignedDocument {
  const AlignedDocument({
    required this.imageBytes,
    required this.width,
    required this.height,
    required this.corners,
    required this.wasAutoDetected,
    this.quality = const QualityReport.ok(),
    this.rotationTurns = 0,
  });

  /// Encoded (PNG/JPEG) bytes of the corrected document.
  final Uint8List imageBytes;
  final int width;
  final int height;

  /// Corners used, in original-capture coordinates.
  final DocumentCorners corners;

  /// False when the user placed the corners by hand.
  final bool wasAutoDetected;

  final QualityReport quality;

  /// Quarter-turns applied during auto-rotation.
  final int rotationTurns;
}
