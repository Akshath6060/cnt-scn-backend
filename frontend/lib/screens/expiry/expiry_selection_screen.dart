import 'package:flutter/material.dart';

import '../../models/expiry_option.dart';
import '../../widgets/expiry_picker.dart';

/// Full-screen expiry chooser (§3 screen 7, §11).
///
/// Used for bulk selection, where a sheet would crowd the summary of what the
/// choice will apply to. Single-contact edits use [ExpiryPickerSheet].
class ExpirySelectionScreen extends StatefulWidget {
  const ExpirySelectionScreen({
    super.key,
    required this.initial,
    this.affectedCount = 1,
  });

  final ExpirySelection initial;

  /// How many contacts this choice will apply to.
  final int affectedCount;

  static Future<ExpirySelection?> open(
    BuildContext context, {
    required ExpirySelection initial,
    int affectedCount = 1,
  }) =>
      Navigator.of(context).push<ExpirySelection>(
        MaterialPageRoute(
          builder: (_) => ExpirySelectionScreen(
            initial: initial,
            affectedCount: affectedCount,
          ),
        ),
      );

  @override
  State<ExpirySelectionScreen> createState() => _ExpirySelectionScreenState();
}

class _ExpirySelectionScreenState extends State<ExpirySelectionScreen> {
  late ExpiryOption _option;
  DateTime? _custom;

  @override
  void initState() {
    super.initState();
    _option = widget.initial.option;
    _custom = widget.initial.customValue;
  }

  bool get _isValid =>
      _option != ExpiryOption.custom ||
      (_custom != null && _custom!.isAfter(DateTime.now()));

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _custom ?? now.add(const Duration(days: 1)),
      firstDate: now, // no past dates (§11)
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _custom ?? now.add(const Duration(hours: 1)),
      ),
    );
    if (time == null || !mounted) return;

    final combined = DateTime(
      date.year, date.month, date.day, time.hour, time.minute,
    );
    if (!combined.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a time in the future.')),
      );
      return;
    }
    setState(() => _custom = combined);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Select expiry')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              widget.affectedCount == 1
                  ? 'Applies to 1 contact.'
                  : 'Applies to ${widget.affectedCount} contacts.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: RadioGroup<ExpiryOption>(
              groupValue: _option,
              onChanged: (value) async {
                if (value == null) return;
                setState(() => _option = value);
                if (value == ExpiryOption.custom) await _pickCustom();
              },
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final option in ExpiryOption.values)
                    RadioListTile<ExpiryOption>(
                      value: option,
                      title: Text(option.label),
                      subtitle: option == ExpiryOption.never
                          ? const Text('Keeps the contact permanently')
                          : option == ExpiryOption.custom && _custom != null
                              ? Text(formatExpiry(_custom))
                              : null,
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isValid
                      ? () => Navigator.of(context).pop(
                            ExpirySelection(
                              option: _option,
                              customValue: _custom,
                            ),
                          )
                      : null,
                  child: const Text('Apply'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
