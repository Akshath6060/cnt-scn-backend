import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/quality_report.dart';
import '../../providers/scan_session_provider.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/document_corner_editor.dart';
import '../processing/processing_screen.dart';

/// Corner review and adjustment before flattening (§4, §26).
///
/// The user always gets the final say on the crop, and any quality warning
/// offers both "Retake" and "Continue Anyway" rather than blocking.
class DocumentPreviewScreen extends ConsumerWidget {
  const DocumentPreviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(scanSessionProvider);
    final notifier = ref.read(scanSessionProvider.notifier);

    final error = session.error;
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Preview')),
        body: AppErrorView(
          error: error,
          onSecondary: () => Navigator.of(context).pop(),
          secondaryLabel: 'Retake photo',
        ),
      );
    }

    final detection = session.detection;
    final bytes = session.captureBytes;
    final corners = session.corners;

    if (detection == null || bytes == null || corners == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Preview')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final quality = detection.quality;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adjust the corners'),
        actions: [
          TextButton(
            onPressed: notifier.resetCorners,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!detection.wasAutoDetected)
            _Banner(
              icon: Icons.crop_free,
              message: 'Page edges were not detected automatically. '
                  'Drag the four corners to match the sheet.',
            ),

          if (quality.hasWarnings) _QualityWarning(quality: quality),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DocumentCornerEditor(
                imageBytes: bytes,
                imageWidth: detection.imageWidth,
                imageHeight: detection.imageHeight,
                corners: corners,
                onCornerMoved: notifier.updateCorner,
              ),
            ),
          ),

          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await notifier.reset();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.replay),
                      label: const Text('Retake'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: session.isBusy
                          ? null
                          : () async {
                              await notifier.alignDocument();
                              if (!context.mounted) return;
                              if (ref.read(scanSessionProvider).phase ==
                                  ScanPhase.aligned) {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const ProcessingScreen(),
                                  ),
                                );
                              }
                            },
                      icon: session.isBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(
                        session.isBusy ? 'Working…' : 'Use this crop',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quality warnings with actionable advice (§26).
class _QualityWarning extends StatelessWidget {
  const _QualityWarning({required this.quality});

  final QualityReport quality;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final issue = quality.primaryIssue;
    if (issue == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: scheme.errorContainer.withValues(alpha: 0.6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber,
              size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.summary,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onErrorContainer,
                  ),
                ),
                Text(
                  issue.suggestion,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
