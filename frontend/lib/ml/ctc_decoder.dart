import 'dart:math' as math;

import 'charset.dart';

/// Result of decoding one sequence of logits.
class CtcDecodeResult {
  const CtcDecodeResult({required this.text, required this.confidence});

  final String text;

  /// Mean probability of the emitted characters, in [0, 1]. Blank-only output
  /// yields 0.
  final double confidence;

  static const empty = CtcDecodeResult(text: '', confidence: 0);
}

/// Greedy (best-path) CTC decoder (§31).
///
/// Collapses repeated class indices then removes the blank, which is the
/// standard decoding for a CTC-trained CRNN. Kept free of any TFLite types so
/// it is unit-testable on the host.
class CtcDecoder {
  const CtcDecoder(this.charset);

  final Charset charset;

  /// Decodes `logits` shaped `[timeSteps][numClasses]`.
  ///
  /// [applySoftmax] should stay true for raw model output; set it to false
  /// when the graph already emits probabilities.
  CtcDecodeResult decode(
    List<List<double>> logits, {
    bool applySoftmax = true,
  }) {
    if (logits.isEmpty) return CtcDecodeResult.empty;

    final buffer = StringBuffer();
    final probabilities = <double>[];
    var previousIndex = -1;

    for (final step in logits) {
      if (step.isEmpty) continue;

      var bestIndex = 0;
      var bestValue = step[0];
      for (var c = 1; c < step.length; c++) {
        if (step[c] > bestValue) {
          bestValue = step[c];
          bestIndex = c;
        }
      }

      // Collapse repeats, drop blanks.
      final isRepeat = bestIndex == previousIndex;
      previousIndex = bestIndex;
      if (isRepeat || bestIndex == charset.blankIndex) continue;

      final char = charset[bestIndex];
      if (char.isEmpty) continue;

      buffer.write(char);
      probabilities.add(
        applySoftmax ? _softmaxAt(step, bestIndex) : bestValue.clamp(0.0, 1.0),
      );
    }

    if (probabilities.isEmpty) return CtcDecodeResult.empty;

    final mean =
        probabilities.reduce((a, b) => a + b) / probabilities.length;

    return CtcDecodeResult(
      text: buffer.toString(),
      confidence: mean.clamp(0.0, 1.0),
    );
  }

  /// Numerically stable softmax probability of a single class.
  double _softmaxAt(List<double> logits, int index) {
    var max = logits[0];
    for (final v in logits) {
      if (v > max) max = v;
    }
    var sum = 0.0;
    for (final v in logits) {
      sum += math.exp(v - max);
    }
    if (sum <= 0 || sum.isNaN || sum.isInfinite) return 0;
    return math.exp(logits[index] - max) / sum;
  }
}
