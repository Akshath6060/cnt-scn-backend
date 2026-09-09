import 'dart:math' as math;

import 'package:contact_scanner/imaging/gray_image.dart';
import 'package:contact_scanner/imaging/kernels/contours.dart';
import 'package:contact_scanner/imaging/kernels/filters.dart';
import 'package:contact_scanner/imaging/kernels/geometry.dart';
import 'package:contact_scanner/imaging/kernels/morphology.dart';
import 'package:contact_scanner/imaging/kernels/threshold.dart';
import 'package:contact_scanner/models/document_scan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// White page (200) on a dark background (40), with a few ink blobs.
GrayImage syntheticPage({int w = 200, int h = 260}) {
  final g = GrayImage.filled(w, h, 40);
  for (var y = 20; y < h - 20; y++) {
    for (var x = 15; x < w - 15; x++) {
      g.set(x, y, 200);
    }
  }
  return g;
}

void main() {
  group('Otsu threshold', () {
    test('separates a bimodal image at a sensible level', () {
      final level = Threshold.otsuLevel(syntheticPage());
      expect(level, greaterThan(40));
      expect(level, lessThan(200));
    });

    test('marks the dark background as ink when inkIsDark', () {
      final binary = Threshold.otsu(syntheticPage());
      // Background (40) is darker, so it becomes foreground here.
      expect(binary.at(2, 2), 255);
      expect(binary.at(100, 130), 0);
    });
  });

  group('adaptive threshold', () {
    test('keeps faint ink visible under a lighting gradient (§5)', () {
      // Page with a strong left-to-right illumination ramp plus faint strokes
      // that are *darker than the paper* but brighter than the dark side.
      final g = GrayImage.filled(120, 60, 0);
      for (var y = 0; y < 60; y++) {
        for (var x = 0; x < 120; x++) {
          final paper = 90 + x; // 90 .. 209
          final isStroke = y >= 25 && y < 32 && x % 20 < 8;
          g.set(x, y, isStroke ? paper - 40 : paper);
        }
      }

      final binary = Threshold.adaptiveMean(g, offset: 10);

      // Strokes found on both the dark and bright sides of the gradient.
      expect(binary.at(2, 28), 255, reason: 'stroke on dark side');
      expect(binary.at(102, 28), 255, reason: 'stroke on bright side');
      // Plain paper is not ink on either side.
      expect(binary.at(12, 5), 0);
      expect(binary.at(112, 5), 0);
    });
  });

  group('illumination correction', () {
    test('flattens a gradient so paper brightness becomes uniform', () {
      final g = GrayImage.filled(120, 60, 0);
      for (var y = 0; y < 60; y++) {
        for (var x = 0; x < 120; x++) {
          g.set(x, y, 80 + x);
        }
      }
      final corrected = Filters.correctIllumination(g, radius: 20);

      final left = corrected.at(10, 30);
      final right = corrected.at(110, 30);
      // Before correction the two differ by ~100 levels.
      expect((left - right).abs(), lessThan(30));
    });
  });

  group('morphology', () {
    test('open removes isolated speckle', () {
      final g = GrayImage.filled(40, 40, 0);
      g.set(20, 20, 255); // single-pixel noise
      final opened = Morphology.open(g, radiusX: 1, radiusY: 1);
      expect(opened.data.any((v) => v != 0), isFalse);
    });

    test('close bridges a one-pixel stroke gap', () {
      final g = GrayImage.filled(40, 40, 0);
      for (var x = 10; x < 20; x++) {
        g.set(x, 20, 255);
      }
      for (var x = 21; x < 30; x++) {
        g.set(x, 20, 255);
      }
      expect(g.at(20, 20), 0);
      final closed = Morphology.close(g, radiusX: 1, radiusY: 0);
      expect(closed.at(20, 20), 255);
    });
  });

  group('connected components', () {
    test('counts separate blobs and merges touching pixels', () {
      final g = GrayImage.filled(60, 60, 0);
      // Blob A
      for (var y = 5; y < 12; y++) {
        for (var x = 5; x < 12; x++) {
          g.set(x, y, 255);
        }
      }
      // Blob B
      for (var y = 30; y < 38; y++) {
        for (var x = 30; x < 40; x++) {
          g.set(x, y, 255);
        }
      }
      final components = Contours.connectedComponents(g, minPixels: 4);
      expect(components, hasLength(2));
      // Sorted by descending pixel count.
      expect(components.first.pixelCount, 8 * 10);
      expect(components.first.box.width, 10);
      expect(components.last.box.left, 5);
    });
  });

  group('homography', () {
    test('recovers an exact mapping and round-trips points', () {
      final from = [
        const Point(0, 0),
        const Point(100, 0),
        const Point(100, 200),
        const Point(0, 200),
      ];
      final to = [
        const Point(10, 20),
        const Point(110, 25),
        const Point(105, 230),
        const Point(5, 215),
      ];
      final h = Geometry.solveHomography(from, to)!;

      for (var i = 0; i < 4; i++) {
        final mapped = Geometry.applyHomography(h, from[i].x, from[i].y);
        expect(mapped.x, closeTo(to[i].x, 1e-6));
        expect(mapped.y, closeTo(to[i].y, 1e-6));
      }
    });

    test('returns null for a degenerate quad', () {
      final collinear = [
        const Point(0, 0),
        const Point(10, 0),
        const Point(20, 0),
        const Point(30, 0),
      ];
      final square = [
        const Point(0, 0),
        const Point(10, 0),
        const Point(10, 10),
        const Point(0, 10),
      ];
      expect(Geometry.solveHomography(collinear, square), isNull);
    });
  });

  group('perspective warp', () {
    test('flattens a skewed quad back into a rectangle', () {
      // Build an image whose "page" is a red-bordered quad on white.
      final src = img.Image(width: 200, height: 200);
      img.fill(src, color: img.ColorRgb8(255, 255, 255));
      // Paint a black marker near one known corner of the quad.
      final corners = const DocumentCorners(
        topLeft: Point(30, 20),
        topRight: Point(170, 40),
        bottomRight: Point(160, 180),
        bottomLeft: Point(20, 160),
      );
      img.fillCircle(src,
          x: 30, y: 20, radius: 4, color: img.ColorRgb8(0, 0, 0));

      final warped = Geometry.warpPerspective(src, corners);

      expect(warped.width, greaterThan(100));
      expect(warped.height, greaterThan(100));
      // The marker painted at the source top-left must land near the
      // destination top-left.
      final p = warped.getPixel(2, 2);
      expect(p.r, lessThan(128), reason: 'top-left marker should be dark');
      // The opposite corner should still be white paper.
      final far = warped.getPixel(warped.width - 3, warped.height - 3);
      expect(far.r, greaterThan(200));
    });
  });

  group('skew estimation', () {
    test('detects a known rotation of text lines', () {
      const angle = 5.0;
      final g = GrayImage.filled(300, 300, 0);
      final radians = angle * math.pi / 180;

      // Draw horizontal "text lines" rotated by +5 degrees about the centre.
      for (var line = 0; line < 8; line++) {
        final baseY = 40.0 + line * 28;
        for (var x = 60; x < 240; x++) {
          final dx = x - 150.0;
          final dy = baseY - 150.0;
          final rx = dx * math.cos(radians) - dy * math.sin(radians) + 150;
          final ry = dx * math.sin(radians) + dy * math.cos(radians) + 150;
          for (var t = 0; t < 3; t++) {
            final px = rx.round(), py = ry.round() + t;
            if (px >= 0 && py >= 0 && px < 300 && py < 300) g.set(px, py, 255);
          }
        }
      }

      final estimated = Geometry.estimateSkewAngle(g);
      // Correcting the skew means rotating by the negative of the applied angle.
      expect(estimated.abs(), closeTo(angle, 1.5));
    });

    test('reports ~0 for already-level text', () {
      final g = GrayImage.filled(200, 200, 0);
      for (var line = 0; line < 6; line++) {
        for (var x = 40; x < 160; x++) {
          g.set(x, 30 + line * 25, 255);
          g.set(x, 31 + line * 25, 255);
        }
      }
      expect(Geometry.estimateSkewAngle(g).abs(), lessThan(1.0));
    });
  });

  group('blur detection (§26)', () {
    test('a blurred page scores far lower than a sharp one', () {
      final sharp = GrayImage.filled(120, 120, 255);
      for (var y = 20; y < 100; y += 8) {
        for (var x = 20; x < 100; x++) {
          sharp.set(x, y, 0);
        }
      }
      final blurred = Filters.gaussianBlur(sharp, radius: 5);

      final sharpScore = Filters.laplacianVariance(sharp);
      final blurredScore = Filters.laplacianVariance(blurred);
      expect(sharpScore, greaterThan(blurredScore * 3));
    });
  });
}
