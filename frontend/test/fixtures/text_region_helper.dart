import 'package:contact_scanner/models/bounding_box.dart';
import 'package:contact_scanner/models/recognized_text.dart';

extension TextRegionForTest on TextRegion {
  static TextRegion make({
    required double x,
    required double y,
    double width = 200,
    double height = 30,
    double confidence = 0.9,
  }) =>
      TextRegion(
        boundingBox: BoundingBox(x: x, y: y, width: width, height: height),
        confidence: confidence,
      );
}
