import 'package:flutter/material.dart';

/// The "Fully Offline" indicator (§18).
///
/// States a fact about the build rather than a live connection status — there
/// is deliberately no cloud-sync indicator to fake.
class OfflineBadge extends StatelessWidget {
  const OfflineBadge({super.key, this.showDescription = false});

  final bool showDescription;

  static const String description =
      'All image processing and contact recognition happen locally on this '
      'device. Images and contact information are never uploaded.';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 16, color: scheme.onPrimaryContainer),
          const SizedBox(width: 6),
          Text(
            'Fully Offline',
            style: TextStyle(
              color: scheme.onPrimaryContainer,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    if (!showDescription) return badge;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        badge,
        const SizedBox(height: 12),
        Text(description, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
