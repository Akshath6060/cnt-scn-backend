import 'package:flutter/material.dart';

import '../../models/contact_candidate.dart';

/// Lets the user pair a leftover name with a leftover number by hand (§10).
class ManualPairingSheet extends StatefulWidget {
  const ManualPairingSheet({
    super.key,
    required this.names,
    required this.phones,
  });

  final List<ContactCandidate> names;
  final List<ContactCandidate> phones;

  /// Returns the chosen `(name, phone)` pair, or `null` if dismissed.
  static Future<(ContactCandidate, ContactCandidate)?> show(
    BuildContext context, {
    required List<ContactCandidate> names,
    required List<ContactCandidate> phones,
  }) =>
      showModalBottomSheet<(ContactCandidate, ContactCandidate)>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => ManualPairingSheet(names: names, phones: phones),
      );

  @override
  State<ManualPairingSheet> createState() => _ManualPairingSheetState();
}

class _ManualPairingSheetState extends State<ManualPairingSheet> {
  ContactCandidate? _name;
  ContactCandidate? _phone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPair = _name != null && _phone != null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pair manually', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),

            Text('Name', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            _ChipPicker(
              items: widget.names,
              selected: _name,
              onSelected: (c) => setState(() => _name = c),
            ),

            const SizedBox(height: 16),
            Text('Phone number', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            _ChipPicker(
              items: widget.phones,
              selected: _phone,
              onSelected: (c) => setState(() => _phone = c),
            ),

            const SizedBox(height: 20),
            FilledButton(
              onPressed: canPair
                  ? () => Navigator.of(context).pop((_name!, _phone!))
                  : null,
              child: const Text('Pair these'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipPicker extends StatelessWidget {
  const _ChipPicker({
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<ContactCandidate> items;
  final ContactCandidate? selected;
  final ValueChanged<ContactCandidate> onSelected;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(
        'Nothing available',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          ChoiceChip(
            label: Text(item.text),
            selected: identical(item, selected),
            onSelected: (_) => onSelected(item),
          ),
      ],
    );
  }
}
