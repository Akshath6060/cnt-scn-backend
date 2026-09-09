import 'package:flutter/material.dart';

import '../../services/duplicate_detection_service.dart';

/// Asks the user what to do about each duplicate (§12).
///
/// Every row starts on [DuplicateResolution.skip] — the safe default — so
/// dismissing without deciding cannot create unwanted copies.
class DuplicateResolutionSheet extends StatefulWidget {
  const DuplicateResolutionSheet({
    super.key,
    required this.duplicates,
    required this.onResolve,
    required this.onResolveAll,
  });

  final List<DuplicateMatch> duplicates;
  final void Function(String contactId, DuplicateResolution resolution) onResolve;
  final void Function(DuplicateResolution resolution) onResolveAll;

  /// Returns true when the user chose to continue saving.
  static Future<bool?> show(
    BuildContext context, {
    required List<DuplicateMatch> duplicates,
    required void Function(String, DuplicateResolution) onResolve,
    required void Function(DuplicateResolution) onResolveAll,
  }) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => DuplicateResolutionSheet(
          duplicates: duplicates,
          onResolve: onResolve,
          onResolveAll: onResolveAll,
        ),
      );

  @override
  State<DuplicateResolutionSheet> createState() =>
      _DuplicateResolutionSheetState();
}

class _DuplicateResolutionSheetState extends State<DuplicateResolutionSheet> {
  late final Map<String, DuplicateResolution> _choices = {
    for (final d in widget.duplicates) d.extracted.id: DuplicateResolution.skip,
  };

  void _set(String id, DuplicateResolution resolution) {
    setState(() => _choices[id] = resolution);
    widget.onResolve(id, resolution);
  }

  void _setAll(DuplicateResolution resolution) {
    setState(() {
      for (final key in _choices.keys) {
        _choices[key] = resolution;
      }
    });
    widget.onResolveAll(resolution);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.duplicates.length} already in your phonebook',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Choose what to do with each. Skipping keeps your existing '
              'contact unchanged.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => _setAll(DuplicateResolution.skip),
                  child: const Text('Skip all'),
                ),
                TextButton(
                  onPressed: () => _setAll(DuplicateResolution.updateExisting),
                  child: const Text('Update all'),
                ),
              ],
            ),
            const Divider(),

            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.duplicates.length,
                separatorBuilder: (_, _) => const Divider(height: 20),
                itemBuilder: (context, index) {
                  final duplicate = widget.duplicates[index];
                  final id = duplicate.extracted.id;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        duplicate.extracted.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${duplicate.extracted.phoneForSaving} · '
                        '${duplicate.description}',
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        'Existing: ${duplicate.existing.displayName}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<DuplicateResolution>(
                        segments: const [
                          ButtonSegment(
                            value: DuplicateResolution.skip,
                            label: Text('Skip'),
                          ),
                          ButtonSegment(
                            value: DuplicateResolution.updateExisting,
                            label: Text('Update'),
                          ),
                          ButtonSegment(
                            value: DuplicateResolution.createAnyway,
                            label: Text('Create'),
                          ),
                        ],
                        selected: {_choices[id]!},
                        onSelectionChanged: (selection) =>
                            _set(id, selection.first),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Back to review'),
            ),
          ],
        ),
      ),
    );
  }
}
