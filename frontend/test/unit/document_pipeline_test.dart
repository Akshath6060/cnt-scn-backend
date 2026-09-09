import 'package:contact_scanner/imaging/dart_image_processor.dart';
import 'package:contact_scanner/imaging/document_image_processor.dart';
import 'package:contact_scanner/models/document_scan.dart';
import 'package:contact_scanner/models/quality_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Renders a synthetic "photo of a page": a white sheet, perspective-skewed
/// inside a dark background, carrying dark text-like bars.
img.Image syntheticPhoto({
  DocumentCorners? corners,
  int width = 600,
  int height = 800,
}) {
  final page = img.Image(width: 420, height: 560);
  img.fill(page, color: img.ColorRgb8(245, 245, 242));
  // Text rows: a short "name" bar and a longer "number" bar.
  for (var row = 0; row < 6; row++) {
    final y = 60 + row * 80;
    img.fillRect(page,
        x1: 40, y1: y, x2: 130, y2: y + 22, color: img.ColorRgb8(25, 25, 30));
    img.fillRect(page,
        x1: 220, y1: y, x2: 370, y2: y + 22, color: img.ColorRgb8(25, 25, 30));
  }

  final scene = img.Image(width: width, height: height);
  img.fill(scene, color: img.ColorRgb8(35, 38, 42));

  final quad = corners ??
      const DocumentCorners(
        topLeft: Point(90, 110),
        topRight: Point(510, 150),
        bottomRight: Point(480, 690),
        bottomLeft: Point(70, 650),
      );

  // Forward-map the page into the scene quad.
  final dst = quad.points;
  final src = <Point>[
    const Point(0, 0),
    Point(page.width.toDouble(), 0),
    Point(page.width.toDouble(), page.height.toDouble()),
    Point(0, page.height.toDouble()),
  ];
  // Solve scene -> page so we can pull pixels for every scene point.
  final inverse = _solve(dst, src);

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final w = inverse[6] * x + inverse[7] * y + inverse[8];
      if (w.abs() < 1e-12) continue;
      final px = (inverse[0] * x + inverse[1] * y + inverse[2]) / w;
      final py = (inverse[3] * x + inverse[4] * y + inverse[5]) / w;
      if (px < 0 || py < 0 || px >= page.width || py >= page.height) continue;
      final p = page.getPixel(px.toInt(), py.toInt());
      scene.setPixelRgb(x, y, p.r, p.g, p.b);
    }
  }
  return scene;
}

List<double> _solve(List<Point> from, List<Point> to) {
  final a = List.generate(8, (_) => List<double>.filled(9, 0));
  for (var i = 0; i < 4; i++) {
    final x = from[i].x, y = from[i].y, u = to[i].x, v = to[i].y;
    a[i * 2] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
    a[i * 2 + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
  }
  for (var col = 0; col < 8; col++) {
    var pivot = col;
    for (var r = col + 1; r < 8; r++) {
      if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
    }
    final t = a[pivot]; a[pivot] = a[col]; a[col] = t;
    final d = a[col][col];
    for (var k = col; k < 9; k++) {
      a[col][k] /= d;
    }
    for (var r = 0; r < 8; r++) {
      if (r == col) continue;
      final f = a[r][col];
      for (var k = col; k < 9; k++) {
        a[r][k] -= f * a[col][k];
      }
    }
  }
  return [for (var i = 0; i < 8; i++) a[i][8], 1.0];
}

void main() {
  const processor = DartImageProcessor();

  group('document detection (§4)', () {
    test('finds the four corners of a skewed page', () {
      final photo = syntheticPhoto();
      final corners = processor.findDocumentCorners(photo);

      expect(corners, isNotNull);
      // Corners should land near the quad the scene was built from.
      expect(corners!.topLeft.x, closeTo(90, 40));
      expect(corners.topLeft.y, closeTo(110, 40));
      expect(corners.bottomRight.x, closeTo(480, 40));
      expect(corners.bottomRight.y, closeTo(690, 40));
    });

    test('returns null when there is no page in frame', () {
      final noise = img.Image(width: 300, height: 300);
      img.fill(noise, color: img.ColorRgb8(40, 40, 40));
      expect(processor.findDocumentCorners(noise), isNull);
    });

    test('detected corners are in full-resolution coordinates (§24)', () {
      // A large capture must still report corners in its own coordinate space,
      // not in the downscaled detection space.
      final photo = syntheticPhoto(width: 2400, height: 3200,
          corners: const DocumentCorners(
            topLeft: Point(360, 440),
            topRight: Point(2040, 600),
            bottomRight: Point(1920, 2760),
            bottomLeft: Point(280, 2600),
          ));
      final corners = processor.findDocumentCorners(photo);
      expect(corners, isNotNull);
      expect(corners!.bottomRight.x, greaterThan(1500));
      expect(corners.bottomRight.y, greaterThan(2000));
    });
  });

  group('perspective correction', () {
    test('flattens the detected page into an upright rectangle', () {
      final photo = syntheticPhoto();
      final corners = processor.findDocumentCorners(photo)!;
      final flat = processor.applyPerspectiveTransform(photo, corners);

      // The flattened page keeps portrait orientation.
      expect(flat.height, greaterThan(flat.width));

      // The dark scene background must be gone: the centre column is paper.
      final centre = flat.getPixel(flat.width ~/ 2, flat.height ~/ 2);
      expect(centre.r, greaterThan(120));
    });
  });

  group('preprocessing (§5)', () {
    test('produces a binarised image that retains the text bars', () {
      final photo = syntheticPhoto();
      final corners = processor.findDocumentCorners(photo)!;
      final flat = processor.applyPerspectiveTransform(photo, corners);

      final result = processor.preprocess(flat, const PreprocessingOptions());

      expect(result.width, greaterThan(0));
      expect(result.processed.width, result.width);

      // Count dark pixels — the text bars must survive binarisation.
      var dark = 0;
      for (var y = 0; y < result.processed.height; y += 2) {
        for (var x = 0; x < result.processed.width; x += 2) {
          if (result.processed.getPixel(x, y).r < 128) dark++;
        }
      }
      final sampled =
          (result.processed.height / 2).ceil() * (result.processed.width / 2).ceil();
      final inkRatio = dark / sampled;
      // Text present, but the page has not been blacked out.
      expect(inkRatio, greaterThan(0.01));
      expect(inkRatio, lessThan(0.45));
    });

    test('debug stages are captured only when requested (§5)', () {
      final photo = syntheticPhoto(width: 300, height: 400);

      final off = processor.preprocess(photo, const PreprocessingOptions());
      expect(off.debugStages.isEmpty, isTrue);

      final on = processor.preprocess(
        photo,
        const PreprocessingOptions(captureDebugStages: true),
      );
      expect(on.debugStages.original, isNotNull);
      expect(on.debugStages.grayscale, isNotNull);
      expect(on.debugStages.thresholded, isNotNull);
      expect(on.debugStages.finalImage, isNotNull);
    });

    test('grayscale output is preserved for recognition, not just binary', () {
      final photo = syntheticPhoto(width: 300, height: 400);
      final result = processor.preprocess(photo, const PreprocessingOptions());

      // The greyscale copy must contain intermediate tones; a binarised copy
      // would only contain 0 and 255.
      final tones = <int>{};
      for (var y = 0; y < result.grayscale.height; y += 3) {
        for (var x = 0; x < result.grayscale.width; x += 3) {
          tones.add(result.grayscale.getPixel(x, y).r.toInt());
        }
      }
      expect(tones.length, greaterThan(2));
    });
  });

  group('quality assessment (§26)', () {
    test('flags a blurred capture', () {
      final photo = syntheticPhoto(width: 400, height: 500);
      final blurred = img.gaussianBlur(photo, radius: 6);
      final report = processor.assessQuality(blurred);
      expect(report.issues, contains(QualityIssue.blurry));
      expect(report.isAcceptable, isFalse);
    });

    test('flags an underexposed capture', () {
      final dark = img.Image(width: 300, height: 300);
      img.fill(dark, color: img.ColorRgb8(18, 18, 18));
      final report = processor.assessQuality(dark);
      expect(report.issues, contains(QualityIssue.tooDark));
    });

    test('flags a page that fills too little of the frame', () {
      final photo = syntheticPhoto(width: 400, height: 500);
      final report = processor.assessQuality(photo, documentAreaRatio: 0.05);
      expect(report.issues, contains(QualityIssue.tooFar));
    });

    test('a clean synthetic page raises no blur warning', () {
      final photo = syntheticPhoto(width: 500, height: 650);
      final report = processor.assessQuality(photo, documentAreaRatio: 0.6);
      expect(report.issues, isNot(contains(QualityIssue.blurry)));
    });
  });
}
