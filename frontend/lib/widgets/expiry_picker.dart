import 'package:flutter/material.dart';

import '../models/expiry_option.dart';

/// Bottom sheet for choosing an expiry (§11).
///
/// Custom expiry cannot be set in the past: the date picker is bounded at
/// "now", and a same-day time earlier than now is rejected before returning.
class ExpiryPickerSheet extends StatefulWidget {
  const ExpiryPickerSheet({
    super.key,
    required this.initial,
    this.title = 'Set expiry',
  });

  final ExpirySelection initial;
  final String title;

  /// Returns `null` when the user dismisses the sheet.
  static Future<ExpirySelection?> show(
    BuildContext context, {
    required ExpirySelection initial,
    String title = 'Set expiry',
  }) =>
      showModalBottomSheet<ExpirySelection>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => ExpiryPickerSheet(initial: initial, title: title),
      );

  @override
  State<ExpiryPickerSheet> createState() => _ExpiryPickerSheetState();
}

class _ExpiryPickerSheetState extends State<ExpiryPickerSheet> {
  late ExpiryOption _option;
  DateTime? _custom;

  @override
  void initState() {
    super.initState();
    _option = widget.initial.option;
    _custom = widget.initial.customValue;
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _custom ?? now.add(const Duration(days: 1)),
      // Prevents choosing a past date outright (§11).
      firstDate: now,
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
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (!combined.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a time in the future.')),
      );
      return;
    }
    setState(() => _custom = combined);
  }

  bool get _isValid {
    if (_option != ExpiryOption.custom) return true;
    return _custom != null && _custom!.isAfter(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),

            Flexible(
              child: SingleChildScrollView(
                child: RadioGroup<ExpiryOption>(
                  groupValue: _option,
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => _option = value);
                    if (value == ExpiryOption.custom) {
                      await _pickCustom();
                    }
                  },
                  child: Column(
                    children: [
                      for (final option in ExpiryOption.values)
                        RadioListTile<ExpiryOption>(
                          value: option,
                          contentPadding: EdgeInsets.zero,
                          title: Text(option.label),
                          subtitle: option == ExpiryOption.never
                              ? const Text('Keeps the contact permanently')
                              : option == ExpiryOption.custom && _custom != null
                                  ? Text(_formatDateTime(_custom!))
                                  : null,
                        ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),
            FilledButton(
              onPressed: _isValid
                  ? () => Navigator.of(context).pop(
                        ExpirySelection(option: _option, customValue: _custom),
                      )
                  : null,
              child: Text(
                _option == ExpiryOption.custom && _custom == null
                    ? 'Choose a date and time'
                    : 'Apply',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Short, locale-agnostic date/time rendering.
String _formatDateTime(DateTime value) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

/// Human-readable countdown, e.g. "2d 4h left" (§17).
String formatRemaining(Duration remaining) {
  if (remaining <= Duration.zero) return 'Expired';
  if (remaining.inDays > 0) {
    return '${remaining.inDays}d ${remaining.inHours % 24}h left';
  }
  if (remaining.inHours > 0) {
    return '${remaining.inHours}h ${remaining.inMinutes % 60}m left';
  }
  if (remaining.inMinutes > 0) return '${remaining.inMinutes}m left';
  return 'Less than a minute left';
}

/// Absolute expiry rendering used in lists.
String formatExpiry(DateTime? expiresAt) =>
    expiresAt == null ? 'Never expires' : _formatDateTime(expiresAt);
