import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/document_scan.dart' as scan;

/// Draggable four-corner overlay for manual document adjustment (§4).
///
/// Corner positions are held in *image* coordinates by the caller; this widget
/// converts to and from widget coordinates so the mapping stays correct at any
/// display size or aspect ratio.
class DocumentCornerEditor extends StatelessWidget {
  const DocumentCornerEditor({
    super.key,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.corners,
    required this.onCornerMoved,
    this.enabled = true,
  });

  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final scan.DocumentCorners corners;

  /// Called with the corner index (0=TL, 1=TR, 2=BR, 3=BL) and its new
  /// position in image coordinates.
  final void Function(int index, scan.Point position) onCornerMoved;

  final bool enabled;

  /// Radius of the draggable handle; also the minimum touch target (§34).
  static const double handleRadius = 14;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Letterbox the image inside the available space, preserving aspect.
        final imageAspect = imageWidth / imageHeight;
        final boxAspect = constraints.maxWidth / constraints.maxHeight;

        final displayWidth = imageAspect > boxAspect
            ? constraints.maxWidth
            : constraints.maxHeight * imageAspect;
        final displayHeight = imageAspect > boxAspect
            ? constraints.maxWidth / imageAspect
            : constraints.maxHeight;

        final offsetX = (constraints.maxWidth - displayWidth) / 2;
        final offsetY = (constraints.maxHeight - displayHeight) / 2;

        final scaleX = displayWidth / imageWidth;
        final scaleY = displayHeight / imageHeight;

        Offset toWidget(scan.Point p) =>
            Offset(offsetX + p.x * scaleX, offsetY + p.y * scaleY);

        scan.Point toImage(Offset o) => scan.Point(
              ((o.dx - offsetX) / scaleX).clamp(0.0, imageWidth.toDouble()),
              ((o.dy - offsetY) / scaleY).clamp(0.0, imageHeight.toDouble()),
            );

        final widgetPoints = corners.points.map(toWidget).toList();

        return Stack(
          children: [
            Positioned(
              left: offsetX,
              top: offsetY,
              width: displayWidth,
              height: displayHeight,
              child: Image.memory(
                imageBytes,
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
            ),

            // Quad outline and dimming outside it.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _QuadPainter(
                    points: widgetPoints,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),

            if (enabled)
              for (var i = 0; i < widgetPoints.length; i++)
                Positioned(
                  left: widgetPoints[i].dx - handleRadius * 1.6,
                  top: widgetPoints[i].dy - handleRadius * 1.6,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      final next = widgetPoints[i] + details.delta;
                      onCornerMoved(i, toImage(next));
                    },
                    child: _CornerHandle(
                      label: const ['TL', 'TR', 'BR', 'BL'][i],
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _CornerHandle extends StatelessWidget {
  const _CornerHandle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The touch area is deliberately larger than the visible dot.
    return Semantics(
      label: 'Document corner $label',
      child: SizedBox(
        width: DocumentCornerEditor.handleRadius * 3.2,
        height: DocumentCornerEditor.handleRadius * 3.2,
        child: Center(
          child: Container(
            width: DocumentCornerEditor.handleRadius * 2,
            height: DocumentCornerEditor.handleRadius * 2,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.onPrimary, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  const _QuadPainter({required this.points, required this.color});

  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length != 4) return;

    final path = Path()..addPolygon(points, true);

    // Dim everything outside the detected page so the crop is obvious.
    final overlay = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      path,
    );
    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_QuadPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}
