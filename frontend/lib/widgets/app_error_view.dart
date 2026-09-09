import 'package:flutter/material.dart';

import '../core/errors/app_exceptions.dart';

/// Renders an [AppException] using only its user-safe message (§25).
///
/// Stack traces and causes are never displayed.
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.primaryLabel,
    this.onSecondary,
    this.secondaryLabel,
    this.compact = false,
  });

  final AppException error;
  final VoidCallback? onRetry;
  final String? primaryLabel;
  final VoidCallback? onSecondary;
  final String? secondaryLabel;
  final bool compact;

  IconData get _icon => switch (error.code) {
    AppErrorCode.cameraPermissionDenied ||
    AppErrorCode.contactsPermissionDenied => Icons.lock_outline,
    AppErrorCode.documentNotDetected ||
    AppErrorCode.poorImageQuality => Icons.crop_free,
    AppErrorCode.modelMissing ||
    AppErrorCode.modelLoadFailed ||
    AppErrorCode.modelIncompatible => Icons.memory_outlined,
    AppErrorCode.noTextDetected ||
    AppErrorCode.noPhoneNumbersDetected => Icons.text_fields,
    _ => Icons.error_outline,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (compact) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(_icon, size: 20, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                error.userMessage,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 48, color: scheme.error),
            const SizedBox(height: 16),
            Text(
              error.userMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (onRetry != null || onSecondary != null) ...[
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  if (onRetry != null)
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: Text(primaryLabel ?? 'Try again'),
                    ),
                  if (onSecondary != null)
                    OutlinedButton(
                      onPressed: onSecondary,
                      child: Text(secondaryLabel ?? 'Back'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
