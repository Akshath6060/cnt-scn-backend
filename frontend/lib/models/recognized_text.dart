import 'bounding_box.dart';

/// One recognised text fragment produced by the handwriting recogniser.
///
/// This is the *only* type that crosses the OCR boundary. Entity extraction
/// consumes it and knows nothing about TFLite, CTC, or image tensors (§35).
class RecognizedText {
  const RecognizedText({
    required this.text,
    required this.confidence,
    required this.boundingBox,
    this.detectionConfidence,
  });

  /// Raw recognised string, exactly as decoded. Never pre-corrected here —
  /// number-specific repair happens later and only for phone-like fields (§8.3).
  final String text;

  /// Recogniser confidence in [0, 1].
  final double confidence;

  /// Location within the flattened document.
  final BoundingBox boundingBox;

  /// Confidence reported by the *detector* for this region, when available.
  final double? detectionConfidence;

  bool get isEmpty => text.trim().isEmpty;

  /// Combined confidence used for ranking, weighting recognition more heavily
  /// than detection because a confidently-detected blob of unreadable
  /// scribble is still useless.
  double get combinedConfidence => detectionConfidence == null
      ? confidence
      : confidence * 0.75 + detectionConfidence! * 0.25;

  RecognizedText copyWith({
    String? text,
    double? confidence,
    BoundingBox? boundingBox,
    double? detectionConfidence,
  }) =>
      RecognizedText(
        text: text ?? this.text,
        confidence: confidence ?? this.confidence,
        boundingBox: boundingBox ?? this.boundingBox,
        detectionConfidence: detectionConfidence ?? this.detectionConfidence,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'confidence': confidence,
        'boundingBox': boundingBox.toJson(),
      };

  factory RecognizedText.fromJson(Map<String, dynamic> json) => RecognizedText(
        text: json['text'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        boundingBox:
            BoundingBox.fromJson(json['boundingBox'] as Map<String, dynamic>),
      );

  @override
  String toString() =>
      'RecognizedText(len=${text.length}, conf=${confidence.toStringAsFixed(2)})';
}

/// A candidate text region emitted by the detection stage, before recognition.
class TextRegion {
  const TextRegion({required this.boundingBox, required this.confidence});

  final BoundingBox boundingBox;
  final double confidence;

  Map<String, dynamic> toJson() => {
        'x': boundingBox.x,
        'y': boundingBox.y,
        'width': boundingBox.width,
        'height': boundingBox.height,
        'confidence': confidence,
      };
}
