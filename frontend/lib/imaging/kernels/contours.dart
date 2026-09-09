import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/bounding_box.dart';
import '../../models/document_scan.dart';
import '../gray_image.dart';

/// One 8-connected blob of foreground pixels.
class ConnectedComponent {
  ConnectedComponent({
    required this.label,
    required this.box,
    required this.pixelCount,
    required this.sumX,
    required this.sumY,
  });

  final int label;
  final BoundingBox box;
  final int pixelCount;
  final double sumX;
  final double sumY;

  double get centroidX => pixelCount == 0 ? 0 : sumX / pixelCount;
  double get centroidY => pixelCount == 0 ? 0 : sumY / pixelCount;

  /// Fraction of the bounding box actually filled with ink. Text has a
  /// moderate fill ratio; a solid rule line or a shadow blob is near 1.
  double get fillRatio => box.area == 0 ? 0 : pixelCount / box.area;
}

/// Connected-component labelling and quadrilateral extraction.
class Contours {
  const Contours._();

  /// Two-pass 8-connected labelling with union-find.
  ///
  /// Foreground is any pixel equal to 255. Returns components sorted by
  /// descending pixel count.
  static List<ConnectedComponent> connectedComponents(
    GrayImage binary, {
    int minPixels = 1,
  }) {
    final w = binary.width, h = binary.height;
    if (w == 0 || h == 0) return const [];

    final labels = Int32List(w * h);
    final parent = <int>[0]; // index 0 unused
    var nextLabel = 1;

    int find(int x) {
      var root = x;
      while (parent[root] != root) {
        root = parent[root];
      }
      // Path compression keeps the second pass near-linear.
      var cur = x;
      while (parent[cur] != root) {
        final next = parent[cur];
        parent[cur] = root;
        cur = next;
      }
      return root;
    }

    void union(int a, int b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[math.max(ra, rb)] = math.min(ra, rb);
    }

    // Pass 1: provisional labels.
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (binary.data[i] == 0) continue;

        // Already-labelled neighbours: W, NW, N, NE.
        final neighbours = <int>[];
        if (x > 0 && labels[i - 1] != 0) neighbours.add(labels[i - 1]);
        if (y > 0) {
          final up = i - w;
          if (x > 0 && labels[up - 1] != 0) neighbours.add(labels[up - 1]);
          if (labels[up] != 0) neighbours.add(labels[up]);
          if (x < w - 1 && labels[up + 1] != 0) neighbours.add(labels[up + 1]);
        }

        if (neighbours.isEmpty) {
          labels[i] = nextLabel;
          parent.add(nextLabel);
          nextLabel++;
        } else {
          var min = neighbours.first;
          for (final n in neighbours) {
            if (n < min) min = n;
          }
          labels[i] = min;
          for (final n in neighbours) {
            union(min, n);
          }
        }
      }
    }

    // Pass 2: resolve equivalences and accumulate statistics.
    final stats = <int, _Accumulator>{};
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (labels[i] == 0) continue;
        final root = find(labels[i]);
        (stats[root] ??= _Accumulator()).add(x, y);
      }
    }

    final result = <ConnectedComponent>[];
    stats.forEach((label, acc) {
      if (acc.count < minPixels) return;
      result.add(
        ConnectedComponent(
          label: label,
          box: BoundingBox(
            x: acc.minX.toDouble(),
            y: acc.minY.toDouble(),
            width: (acc.maxX - acc.minX + 1).toDouble(),
            height: (acc.maxY - acc.minY + 1).toDouble(),
          ),
          pixelCount: acc.count,
          sumX: acc.sumX.toDouble(),
          sumY: acc.sumY.toDouble(),
        ),
      );
    });

    result.sort((a, b) => b.pixelCount.compareTo(a.pixelCount));
    return result;
  }

  /// Extracts the corner quadrilateral of a foreground mask.
  ///
  /// Uses the extreme-sum heuristic: for a convex, roughly rectangular blob the
  /// corner nearest the origin minimises `x + y`, the opposite corner maximises
  /// it, and the other two extremise `x - y`. This is far more stable on a
  /// noisy hand-held capture than polygon approximation, which tends to produce
  /// five- and six-sided contours when a page edge is partly occluded.
  static DocumentCorners? cornersOfMask(GrayImage mask, int targetLabel,
      {Int32List? labels}) {
    var minSum = double.infinity, maxSum = -double.infinity;
    var minDiff = double.infinity, maxDiff = -double.infinity;
    Point? tl, br, bl, tr;

    for (var y = 0; y < mask.height; y++) {
      for (var x = 0; x < mask.width; x++) {
        if (mask.data[y * mask.width + x] == 0) continue;
        final sum = (x + y).toDouble();
        final diff = (x - y).toDouble();
        if (sum < minSum) {
          minSum = sum;
          tl = Point(x.toDouble(), y.toDouble());
        }
        if (sum > maxSum) {
          maxSum = sum;
          br = Point(x.toDouble(), y.toDouble());
        }
        if (diff < minDiff) {
          minDiff = diff;
          bl = Point(x.toDouble(), y.toDouble());
        }
        if (diff > maxDiff) {
          maxDiff = diff;
          tr = Point(x.toDouble(), y.toDouble());
        }
      }
    }

    if (tl == null || tr == null || br == null || bl == null) return null;
    return DocumentCorners(
      topLeft: tl,
      topRight: tr,
      bottomRight: br,
      bottomLeft: bl,
    );
  }

  /// Renders a single component back into a mask, so corner extraction can be
  /// restricted to the page blob and ignore background clutter.
  static GrayImage maskOfLargestComponent(GrayImage binary) {
    final components = connectedComponents(binary, minPixels: 32);
    if (components.isEmpty) return binary.emptyLike();

    final largest = components.first;
    final mask = binary.emptyLike();

    // Re-flood only within the component's bounding box: cheaper than a second
    // full-image labelling pass and sufficient because components are disjoint.
    final x0 = largest.box.left.toInt();
    final y0 = largest.box.top.toInt();
    final x1 = math.min(largest.box.right.toInt(), binary.width - 1);
    final y1 = math.min(largest.box.bottom.toInt(), binary.height - 1);

    final visited = Uint8List(binary.width * binary.height);
    final queue = <int>[];

    // Seed from the component centroid, falling back to any foreground pixel.
    var seed = -1;
    final cx = largest.centroidX.round().clamp(x0, x1);
    final cy = largest.centroidY.round().clamp(y0, y1);
    if (binary.data[cy * binary.width + cx] != 0) {
      seed = cy * binary.width + cx;
    } else {
      outer:
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          if (binary.data[y * binary.width + x] != 0) {
            seed = y * binary.width + x;
            break outer;
          }
        }
      }
    }
    if (seed < 0) return mask;

    queue.add(seed);
    visited[seed] = 1;

    while (queue.isNotEmpty) {
      final i = queue.removeLast();
      mask.data[i] = 255;
      final x = i % binary.width;
      final y = i ~/ binary.width;

      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= binary.width || ny >= binary.height) {
            continue;
          }
          final ni = ny * binary.width + nx;
          if (visited[ni] == 1 || binary.data[ni] == 0) continue;
          visited[ni] = 1;
          queue.add(ni);
        }
      }
    }
    return mask;
  }
}

class _Accumulator {
  int count = 0;
  int minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;
  int sumX = 0, sumY = 0;

  void add(int x, int y) {
    count++;
    sumX += x;
    sumY += y;
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
  }
}
