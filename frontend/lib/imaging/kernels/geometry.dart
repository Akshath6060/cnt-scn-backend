import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../models/document_scan.dart';
import '../gray_image.dart';

/// Perspective correction, rotation, and skew estimation (§4).
class Geometry {
  const Geometry._();

  // ── Homography ────────────────────────────────────────────────────────────

  /// Solves the 3x3 homography H such that `to ≈ H * from`, with `h22 = 1`.
  ///
  /// Each point correspondence contributes two linear equations, so four
  /// points give the 8x8 system solved here by Gaussian elimination with
  /// partial pivoting. Returns `null` when the configuration is degenerate
  /// (three collinear corners, say), which the caller must treat as
  /// "detection failed" rather than crashing.
  static Float64List? solveHomography(List<Point> from, List<Point> to) {
    if (from.length != 4 || to.length != 4) return null;

    final a = List.generate(8, (_) => Float64List(9));
    for (var i = 0; i < 4; i++) {
      final x = from[i].x, y = from[i].y;
      final u = to[i].x, v = to[i].y;

      final r0 = a[i * 2];
      r0[0] = x; r0[1] = y; r0[2] = 1;
      r0[3] = 0; r0[4] = 0; r0[5] = 0;
      r0[6] = -u * x; r0[7] = -u * y; r0[8] = u;

      final r1 = a[i * 2 + 1];
      r1[0] = 0; r1[1] = 0; r1[2] = 0;
      r1[3] = x; r1[4] = y; r1[5] = 1;
      r1[6] = -v * x; r1[7] = -v * y; r1[8] = v;
    }

    // Gaussian elimination with partial pivoting.
    for (var col = 0; col < 8; col++) {
      var pivot = col;
      for (var row = col + 1; row < 8; row++) {
        if (a[row][col].abs() > a[pivot][col].abs()) pivot = row;
      }
      if (a[pivot][col].abs() < 1e-9) return null; // singular
      if (pivot != col) {
        final tmp = a[pivot];
        a[pivot] = a[col];
        a[col] = tmp;
      }

      final diag = a[col][col];
      for (var k = col; k < 9; k++) {
        a[col][k] /= diag;
      }
      for (var row = 0; row < 8; row++) {
        if (row == col) continue;
        final factor = a[row][col];
        if (factor == 0) continue;
        for (var k = col; k < 9; k++) {
          a[row][k] -= factor * a[col][k];
        }
      }
    }

    final h = Float64List(9);
    for (var i = 0; i < 8; i++) {
      h[i] = a[i][8];
    }
    h[8] = 1.0;
    return h;
  }

  /// Applies a homography to a point.
  static Point applyHomography(Float64List h, double x, double y) {
    final w = h[6] * x + h[7] * y + h[8];
    if (w.abs() < 1e-12) return Point(0, 0);
    return Point(
      (h[0] * x + h[1] * y + h[2]) / w,
      (h[3] * x + h[4] * y + h[5]) / w,
    );
  }

  /// Output size for a warped quadrilateral: the longest opposing edges, so
  /// no part of the page is compressed.
  static (int, int) outputSizeFor(DocumentCorners c, {int maxLongEdge = 2200}) {
    double dist(Point a, Point b) =>
        math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

    final width = math.max(
      dist(c.topLeft, c.topRight),
      dist(c.bottomLeft, c.bottomRight),
    );
    final height = math.max(
      dist(c.topLeft, c.bottomLeft),
      dist(c.topRight, c.bottomRight),
    );

    var w = math.max(width.round(), 16);
    var h = math.max(height.round(), 16);

    // Bound memory on large captures (§24).
    final longEdge = math.max(w, h);
    if (longEdge > maxLongEdge) {
      final scale = maxLongEdge / longEdge;
      w = math.max((w * scale).round(), 16);
      h = math.max((h * scale).round(), 16);
    }
    return (w, h);
  }

  /// Perspective-corrects [src] so that [corners] becomes a full rectangle.
  ///
  /// Uses inverse mapping (destination → source) with bilinear sampling, which
  /// is what avoids the holes a forward map would leave.
  static img.Image warpPerspective(
    img.Image src,
    DocumentCorners corners, {
    int maxLongEdge = 2200,
  }) {
    final (outW, outH) = outputSizeFor(corners, maxLongEdge: maxLongEdge);

    // Solve destination-rectangle -> source-quad so we can pull pixels.
    final destination = <Point>[
      const Point(0, 0),
      Point(outW.toDouble(), 0),
      Point(outW.toDouble(), outH.toDouble()),
      Point(0, outH.toDouble()),
    ];
    final h = solveHomography(destination, corners.points);
    if (h == null) return src;

    final dst = img.Image(width: outW, height: outH);
    final maxX = src.width - 1;
    final maxY = src.height - 1;

    for (var y = 0; y < outH; y++) {
      for (var x = 0; x < outW; x++) {
        final p = applyHomography(h, x.toDouble(), y.toDouble());
        if (p.x < 0 || p.y < 0 || p.x > maxX || p.y > maxY) {
          dst.setPixelRgb(x, y, 255, 255, 255);
          continue;
        }
        _sampleBilinear(src, p.x, p.y, dst, x, y);
      }
    }
    return dst;
  }

  static void _sampleBilinear(
    img.Image src,
    double sx,
    double sy,
    img.Image dst,
    int dx,
    int dy,
  ) {
    final x0 = sx.floor();
    final y0 = sy.floor();
    final x1 = math.min(x0 + 1, src.width - 1);
    final y1 = math.min(y0 + 1, src.height - 1);
    final fx = sx - x0;
    final fy = sy - y0;

    final p00 = src.getPixel(x0, y0);
    final p10 = src.getPixel(x1, y0);
    final p01 = src.getPixel(x0, y1);
    final p11 = src.getPixel(x1, y1);

    double mix(num a, num b, num c, num d) {
      final top = a + (b - a) * fx;
      final bottom = c + (d - c) * fx;
      return top + (bottom - top) * fy;
    }

    dst.setPixelRgb(
      dx,
      dy,
      mix(p00.r, p10.r, p01.r, p11.r).round().clamp(0, 255),
      mix(p00.g, p10.g, p01.g, p11.g).round().clamp(0, 255),
      mix(p00.b, p10.b, p01.b, p11.b).round().clamp(0, 255),
    );
  }

  // ── Skew ──────────────────────────────────────────────────────────────────

  /// Estimates page skew in degrees using a horizontal projection profile.
  ///
  /// When lines of text are level, ink concentrates into a few rows and the
  /// variance of the row-sum profile peaks. Sweeping candidate angles and
  /// taking the maximum is robust on sparse handwriting, where a Hough
  /// transform tends to lock onto stray rule lines.
  static double estimateSkewAngle(
    GrayImage binary, {
    double maxAngle = 10,
    double step = 0.5,
  }) {
    // Work on a small copy: skew is a global property and does not need
    // full resolution.
    final scale = 400 / math.max(binary.width, binary.height);
    final work = scale < 1
        ? _resizeBinary(binary, (binary.width * scale).round().clamp(16, 400),
            (binary.height * scale).round().clamp(16, 400))
        : binary;

    var bestAngle = 0.0;
    var bestScore = -1.0;

    for (var angle = -maxAngle; angle <= maxAngle; angle += step) {
      final score = _projectionVariance(work, angle);
      if (score > bestScore) {
        bestScore = score;
        bestAngle = angle;
      }
    }
    return bestAngle;
  }

  static GrayImage _resizeBinary(GrayImage src, int w, int h) {
    final dst = GrayImage(w, h, Uint8List(w * h));
    for (var y = 0; y < h; y++) {
      final sy = (y * src.height / h).floor().clamp(0, src.height - 1);
      for (var x = 0; x < w; x++) {
        final sx = (x * src.width / w).floor().clamp(0, src.width - 1);
        dst.data[y * w + x] = src.data[sy * src.width + sx];
      }
    }
    return dst;
  }

  /// Variance of the row-sum profile after a virtual rotation by [angle].
  static double _projectionVariance(GrayImage binary, double angle) {
    final radians = angle * math.pi / 180;
    final sin = math.sin(radians);
    final cos = math.cos(radians);
    final cx = binary.width / 2;
    final cy = binary.height / 2;

    final profile = Int32List(binary.height);

    for (var y = 0; y < binary.height; y++) {
      for (var x = 0; x < binary.width; x++) {
        if (binary.data[y * binary.width + x] == 0) continue;
        final dx = x - cx;
        final dy = y - cy;
        final ry = (-dx * sin + dy * cos + cy).round();
        if (ry >= 0 && ry < binary.height) profile[ry]++;
      }
    }

    var sum = 0.0;
    for (final v in profile) {
      sum += v;
    }
    if (sum == 0) return 0;
    final mean = sum / profile.length;

    var variance = 0.0;
    for (final v in profile) {
      final d = v - mean;
      variance += d * d;
    }
    return variance / profile.length;
  }

  /// Rotates about the centre with bilinear sampling and a white background.
  static img.Image rotate(img.Image src, double degrees) {
    if (degrees.abs() < 0.05) return src;
    return img.copyRotate(src, angle: degrees, interpolation: img.Interpolation.linear);
  }

  /// Quarter-turn rotation used for automatic orientation.
  static img.Image rotateQuarterTurns(img.Image src, int turns) {
    final t = ((turns % 4) + 4) % 4;
    if (t == 0) return src;
    return img.copyRotate(src, angle: t * 90);
  }
}
