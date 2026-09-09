import 'package:flutter/material.dart';

import '../models/processing_result.dart';

/// Honest progress display for the processing screen (§23).
///
/// Shows the named stage, and a determinate bar **only** where a real count
/// exists (recognition, which knows how many regions remain). Every other
/// stage shows an indeterminate bar rather than a fabricated percentage.
class ProcessingProgressView extends StatelessWidget {
  const ProcessingProgressView({
    super.key,
    required this.progress,
    this.usingMockRecognizer = false,
  });

  final ProcessingProgress? progress;
  final bool usingMockRecognizer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stage = progress?.stage ?? ProcessingStage.preparingImage;
    final itemFraction = progress?.itemFraction;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            stage.message,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 20),

          // Determinate only where the count is genuine.
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: itemFraction,
              minHeight: 6,
            ),
          ),

          if (progress?.hasItemProgress ?? false) ...[
            const SizedBox(height: 10),
            Text(
              '${progress!.itemsDone} of ${progress!.itemsTotal} regions read',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],

          const SizedBox(height: 28),
          _StageList(current: stage),

          if (usingMockRecognizer) ...[
            const SizedBox(height: 24),
            _MockWarning(),
          ],
        ],
      ),
    );
  }
}

/// Checklist of pipeline stages, so the user can see what has been done.
class _StageList extends StatelessWidget {
  const _StageList({required this.current});

  final ProcessingStage current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stages = ProcessingStage.values
        .where((s) => s != ProcessingStage.done)
        .toList();

    return Column(
      children: [
        for (final stage in stages)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  stage.index < current.index
                      ? Icons.check_circle
                      : stage == current
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                  size: 17,
                  color: stage.index < current.index
                      ? scheme.primary
                      : stage == current
                          ? scheme.primary
                          : scheme.outlineVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    stage.message,
                    style: TextStyle(
                      fontSize: 14,
                      color: stage.index <= current.index
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                      fontWeight: stage == current
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MockWarning extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.science_outlined,
              size: 18, color: scheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Development mode: results come from the mock recogniser, '
              'not the trained model.',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
