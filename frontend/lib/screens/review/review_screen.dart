import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/contact_candidate.dart';
import '../../models/expiry_option.dart';
import '../../models/extracted_contact.dart';
import '../../providers/review_provider.dart';
import '../../providers/scan_session_provider.dart';
import '../../services/duplicate_detection_service.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/contact_review_card.dart';
import '../expiry/expiry_selection_screen.dart';
import 'contact_edit_screen.dart';
import 'duplicate_resolution_sheet.dart';
import 'manual_pairing_sheet.dart';
import 'save_summary_screen.dart';

/// Review and correct extracted contacts (§10, §34).
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reviewProvider);
    final notifier = ref.read(reviewProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${state.contacts.length} contacts found'),
        actions: [
          IconButton(
            tooltip: 'Add contact manually',
            onPressed: () => _openManualContact(context, ref),
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
          TextButton(
            onPressed: state.contacts.isEmpty
                ? null
                : () => notifier.selectAll(!state.allSelected),
            child: Text(state.allSelected ? 'Deselect all' : 'Select all'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.usedMockRecognizer) const _MockBanner(),
          if (state.needsAttentionCount > 0)
            _AttentionBanner(count: state.needsAttentionCount),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: AppErrorView(error: state.error!, compact: true),
            ),

          Expanded(
            child: state.contacts.isEmpty && !state.hasLeftovers
                ? const _EmptyState()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      for (final contact in state.contacts) ...[
                        ContactReviewCard(
                          key: ValueKey(contact.id),
                          contact: contact,
                          onNameChanged: (v) =>
                              notifier.editName(contact.id, v),
                          onPhoneChanged: (v) =>
                              notifier.editPhone(contact.id, v),
                          onSelectedToggled: () =>
                              notifier.toggleSelected(contact.id),
                          onExpiryChanged: (e) =>
                              notifier.setExpiry(contact.id, e),
                          onDeleted: () => notifier.remove(contact.id),
                          onOpenEditor: () async {
                            final edited = await ContactEditScreen.open(
                              context,
                              contact,
                            );
                            if (edited == null) return;
                            notifier.editName(edited.id, edited.name);
                            notifier.editPhone(edited.id, edited.phone);
                            notifier.setExpiry(edited.id, edited.expiry);
                          },
                        ),
                        const SizedBox(height: 12),
                      ],

                      if (state.hasLeftovers)
                        _LeftoversSection(
                          names: state.unmatchedNames,
                          phones: state.unmatchedPhones,
                          onAdopt: notifier.adoptUnmatched,
                          onPairManually: () =>
                              _openManualPairing(context, ref),
                        ),
                    ],
                  ),
          ),

          _BulkActionBar(
            selectedCount: state.selectedCount,
            isSaving: state.isSaving,
            canSave: state.canSave,
            onSetExpiry: () async {
              // A full screen rather than a sheet: a bulk change needs to say
              // plainly how many contacts it will affect.
              final selection = await ExpirySelectionScreen.open(
                context,
                initial: const ExpirySelection.permanent(),
                affectedCount: state.selectedCount,
              );
              if (selection != null) {
                notifier.setExpiryForSelected(selection);
              }
            },
            onMarkPermanent: notifier.markSelectedPermanent,
            onSave: () => _save(context, ref),
          ),
        ],
      ),
      bottomNavigationBar: state.contacts.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  '${state.selectedCount} selected',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
    );
  }

  Future<void> _openManualContact(BuildContext context, WidgetRef ref) async {
    final draft = ExtractedContact(
      id: 'manual_draft',
      name: '',
      phone: '',
      confidence: 1.0,
      wasEditedByUser: true,
    );
    final edited = await ContactEditScreen.open(context, draft);
    if (edited == null || !context.mounted) return;
    ref
        .read(reviewProvider.notifier)
        .addManualContact(
          name: edited.name,
          phone: edited.phone,
          expiry: edited.expiry,
        );
  }

  Future<void> _openManualPairing(BuildContext context, WidgetRef ref) async {
    final state = ref.read(reviewProvider);
    final result = await ManualPairingSheet.show(
      context,
      names: state.unmatchedNames,
      phones: state.unmatchedPhones,
    );
    if (result != null) {
      ref.read(reviewProvider.notifier).pairManually(result.$1, result.$2);
    }
  }

  /// Save flow: check duplicates, resolve them, then write (§12, §13).
  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(reviewProvider.notifier);

    final duplicates = await notifier.checkDuplicates();
    if (!context.mounted) return;

    if (duplicates.isNotEmpty) {
      final proceed = await DuplicateResolutionSheet.show(
        context,
        duplicates: duplicates,
        onResolve: notifier.resolveDuplicate,
        onResolveAll: notifier.resolveAllDuplicates,
      );
      if (proceed != true || !context.mounted) return;
    }

    try {
      final summary = await notifier.save();
      if (!context.mounted) return;

      // The scan is finished: drop working images (§19).
      await ref.read(scanSessionProvider.notifier).reset();
      if (!context.mounted) return;

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SaveSummaryScreen(summary: summary),
        ),
      );
    } catch (_) {
      // The error is already in state and rendered inline.
    }
  }
}

class _BulkActionBar extends StatelessWidget {
  const _BulkActionBar({
    required this.selectedCount,
    required this.isSaving,
    required this.canSave,
    required this.onSetExpiry,
    required this.onMarkPermanent,
    required this.onSave,
  });

  final int selectedCount;
  final bool isSaving;
  final bool canSave;
  final VoidCallback onSetExpiry;
  final VoidCallback onMarkPermanent;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = selectedCount > 0;

    return Material(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: enabled ? onSetExpiry : null,
                    icon: const Icon(Icons.timer_outlined, size: 18),
                    label: const Text('Set expiry'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: enabled ? onMarkPermanent : null,
                    icon: const Icon(Icons.all_inclusive, size: 18),
                    label: const Text('Permanent'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (enabled && canSave && !isSaving) ? onSave : null,
                icon: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  isSaving ? 'Saving…' : 'Save $selectedCount to phonebook',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeftoversSection extends StatelessWidget {
  const _LeftoversSection({
    required this.names,
    required this.phones,
    required this.onAdopt,
    required this.onPairManually,
  });

  final List<ContactCandidate> names;
  final List<ContactCandidate> phones;
  final ValueChanged<ContactCandidate> onAdopt;
  final VoidCallback onPairManually;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Not matched',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'These were read from the page but could not be paired. '
              'Nothing has been discarded.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            for (final candidate in [...names, ...phones])
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  candidate.isPhone
                      ? Icons.phone_outlined
                      : Icons.person_outline,
                  size: 20,
                ),
                title: Text(candidate.text),
                subtitle: Text(candidate.entityType.label),
                trailing: TextButton(
                  onPressed: () => onAdopt(candidate),
                  child: const Text('Add'),
                ),
              ),

            if (names.isNotEmpty && phones.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onPairManually,
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Pair a name with a number'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MockBanner extends StatelessWidget {
  const _MockBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.science_outlined,
            size: 18,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'These results came from the mock recogniser, not a trained model.',
              style: TextStyle(fontSize: 13, color: scheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionBanner extends StatelessWidget {
  const _AttentionBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer.withValues(alpha: 0.45),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count ${count == 1 ? 'entry needs' : 'entries need'} '
              'a quick check before saving.',
              style: TextStyle(fontSize: 13, color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 48),
            const SizedBox(height: 16),
            Text(
              'No contacts were extracted from this page.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Try a sharper photo with the sheet filling the frame.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Re-exported so the review screen's collaborators share one import.
typedef DuplicateResolutionCallback =
    void Function(String contactId, DuplicateResolution resolution);
