import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/expiry_option.dart';
import '../../models/temporary_contact.dart';
import '../../providers/temporary_contacts_provider.dart';
import '../../services/contact_service.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/expiry_picker.dart';

/// Locally-registered temporary contacts (§17).
///
/// Opening this screen runs a cleanup pass first (§15 trigger 4), so what is
/// listed already reflects any expiry that came due while the app was closed.
class TemporaryContactsScreen extends ConsumerStatefulWidget {
  const TemporaryContactsScreen({super.key});

  @override
  ConsumerState<TemporaryContactsScreen> createState() =>
      _TemporaryContactsScreenState();
}

class _TemporaryContactsScreenState
    extends ConsumerState<TemporaryContactsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(temporaryContactsProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(temporaryContactsProvider);
    final notifier = ref.read(temporaryContactsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Temporary Contacts'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: notifier.refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: notifier.refresh,
        child: _buildBody(state, notifier),
      ),
    );
  }

  Widget _buildBody(
    TemporaryContactsState state,
    TemporaryContactsNotifier notifier,
  ) {
    if (state.error != null) {
      return AppErrorView(error: state.error!, onRetry: notifier.refresh);
    }
    if (state.isLoading && state.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Icon(Icons.timer_off_outlined, size: 48),
          SizedBox(height: 16),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'No temporary contacts yet.\n'
              'Mark contacts temporary when you save them and they will be '
              'removed automatically when they expire.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        for (final contact in state.active) ...[
          _TemporaryContactCard(
            contact: contact,
            onConvert: () => notifier.convertToPermanent(contact),
            onDelete: () => _confirmDelete(context, notifier, contact),
            onExtend: (duration) => notifier.extend(contact, duration),
            onChangeExpiry: () => _changeExpiry(context, notifier, contact),
          ),
          const SizedBox(height: 12),
        ],

        if (state.finished.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'History',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: notifier.clearHistory,
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final contact in state.finished)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                contact.status == TemporaryContactStatus.deleted
                    ? Icons.check_circle_outline
                    : Icons.help_outline,
                size: 20,
              ),
              title: Text(contact.name),
              subtitle: Text(
                '${contact.phone} · ${contact.status.label}',
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    TemporaryContactsNotifier notifier,
    TemporaryContact contact,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete now?'),
        content: Text(
          '${contact.name} will be removed from your phonebook immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final outcome = await notifier.deleteNow(contact);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (outcome) {
          ContactDeletionOutcome.deleted => 'Removed from your phonebook.',
          ContactDeletionOutcome.missing =>
            'That contact was already gone from your phonebook.',
          ContactDeletionOutcome.failed =>
            'It could not be removed. It will be retried automatically.',
        }),
      ),
    );
  }

  Future<void> _changeExpiry(
    BuildContext context,
    TemporaryContactsNotifier notifier,
    TemporaryContact contact,
  ) async {
    final selection = await ExpiryPickerSheet.show(
      context,
      initial: const ExpirySelection(option: ExpiryOption.oneDay),
      title: 'Change expiry',
    );
    if (selection == null) return;
    await notifier.changeExpiry(contact, selection.resolve(DateTime.now()));
  }
}

class _TemporaryContactCard extends StatelessWidget {
  const _TemporaryContactCard({
    required this.contact,
    required this.onConvert,
    required this.onDelete,
    required this.onExtend,
    required this.onChangeExpiry,
  });

  final TemporaryContact contact;
  final VoidCallback onConvert;
  final VoidCallback onDelete;
  final ValueChanged<Duration> onExtend;
  final VoidCallback onChangeExpiry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final remaining = contact.remainingAt(DateTime.now());
    final isUrgent = remaining != null && remaining.inHours < 1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    contact.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                _StatusChip(status: contact.status),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              contact.phone,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 16,
                  color: isUrgent ? scheme.error : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    contact.isPermanent
                        ? 'Never expires'
                        : '${remaining == null ? '' : '${formatRemaining(remaining)} · '}'
                            '${formatExpiry(contact.expiresAt)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isUrgent ? scheme.error : scheme.onSurfaceVariant,
                      fontWeight:
                          isUrgent ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => onExtend(const Duration(hours: 24)),
                  child: const Text('+24h'),
                ),
                TextButton(
                  onPressed: onChangeExpiry,
                  child: const Text('Change'),
                ),
                TextButton(
                  onPressed: onConvert,
                  child: const Text('Keep'),
                ),
                TextButton(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  child: const Text('Delete now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final TemporaryContactStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      TemporaryContactStatus.active => scheme.primary,
      TemporaryContactStatus.expired => scheme.tertiary,
      TemporaryContactStatus.error => scheme.error,
      _ => scheme.outline,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
