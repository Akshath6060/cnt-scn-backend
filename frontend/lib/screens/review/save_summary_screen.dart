import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/review_provider.dart';
import '../temporary_contacts/temporary_contacts_screen.dart';

/// Confirmation shown after saving (§10).
class SaveSummaryScreen extends ConsumerWidget {
  const SaveSummaryScreen({super.key, required this.summary});

  final SaveSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final allGood = !summary.hasFailures && summary.saved > 0;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                Icon(
                  allGood ? Icons.check_circle_outline : Icons.info_outline,
                  size: 64,
                  color: allGood ? scheme.primary : scheme.tertiary,
                ),
                const SizedBox(height: 20),
                Text(
                  summary.saved == 0
                      ? 'Nothing new was saved'
                      : '${summary.saved} '
                          '${summary.saved == 1 ? 'contact' : 'contacts'} saved',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _Row(label: 'Saved to phonebook', value: summary.saved),
                        if (summary.updated > 0)
                          _Row(label: 'Existing updated', value: summary.updated),
                        if (summary.skipped > 0)
                          _Row(
                            label: 'Skipped as duplicates',
                            value: summary.skipped,
                          ),
                        if (summary.temporaryRegistered > 0)
                          _Row(
                            label: 'Tracked as temporary',
                            value: summary.temporaryRegistered,
                          ),
                        if (summary.failed > 0)
                          _Row(
                            label: 'Could not be saved',
                            value: summary.failed,
                            isError: true,
                          ),
                      ],
                    ),
                  ),
                ),

                if (summary.temporaryRegistered > 0) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Temporary contacts are removed from your phonebook '
                    'automatically when they expire.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],

                const Spacer(),

                if (summary.temporaryRegistered > 0)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => const TemporaryContactsScreen(),
                        ),
                      ),
                      child: const Text('View temporary contacts'),
                    ),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context)
                        .popUntil((route) => route.isFirst),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.isError = false});

  final String label;
  final int value;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '$value',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isError ? scheme.error : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
