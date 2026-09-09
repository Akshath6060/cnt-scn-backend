import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Compact confidence indicator (§10).
///
/// Low-confidence entries are clearly identifiable without colour-coding the
/// entire card, and the label is text as well as colour so the signal survives
/// for colour-blind users.
class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge({
    super.key,
    required this.confidence,
    this.showPercentage = true,
  });

  final double confidence;
  final bool showPercentage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.confidenceColor(confidence);
    final label = scheme.confidenceLabel(confidence);

    return Tooltip(
      message: 'Recognition confidence: '
          '${(confidence * 100).round()}%',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              confidence >= 0.65 ? Icons.check_circle_outline : Icons.warning_amber,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              showPercentage ? '$label ${(confidence * 100).round()}%' : label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
