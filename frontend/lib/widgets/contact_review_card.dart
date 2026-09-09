import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/expiry_option.dart';
import '../models/extracted_contact.dart';
import 'confidence_badge.dart';
import 'expiry_picker.dart';

/// Editable card for one extracted contact (§10).
///
/// Optimised for speed because a sheet may hold dozens of rows (§34): both
/// fields are inline-editable, selection is a single tap, and expiry is one
/// tap away.
class ContactReviewCard extends StatefulWidget {
  const ContactReviewCard({
    super.key,
    required this.contact,
    required this.onNameChanged,
    required this.onPhoneChanged,
    required this.onSelectedToggled,
    required this.onExpiryChanged,
    required this.onDeleted,
    required this.onOpenEditor,
  });

  final ExtractedContact contact;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onPhoneChanged;
  final VoidCallback onSelectedToggled;
  final ValueChanged<ExpirySelection> onExpiryChanged;
  final VoidCallback onDeleted;

  /// Opens the full-screen editor for the awkward cases.
  final VoidCallback onOpenEditor;

  @override
  State<ContactReviewCard> createState() => _ContactReviewCardState();
}

class _ContactReviewCardState extends State<ContactReviewCard> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.contact.name);
    _phoneController = TextEditingController(text: widget.contact.phone);
  }

  @override
  void didUpdateWidget(ContactReviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep controllers in step when the value changes from outside (bulk
    // actions), without stealing the cursor while the user is typing.
    if (widget.contact.name != _nameController.text &&
        widget.contact.name != oldWidget.contact.name) {
      _nameController.text = widget.contact.name;
    }
    if (widget.contact.phone != _phoneController.text &&
        widget.contact.phone != oldWidget.contact.phone) {
      _phoneController.text = widget.contact.phone;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contact = widget.contact;
    final scheme = Theme.of(context).colorScheme;
    final needsAttention = contact.needsAttention;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          // A single accent border carries the "check this one" signal.
          color: needsAttention
              ? scheme.error.withValues(alpha: 0.55)
              : contact.isSelected
                  ? scheme.primary.withValues(alpha: 0.5)
                  : scheme.outlineVariant,
          width: needsAttention || contact.isSelected ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: contact.isSelected,
                  onChanged: (_) => widget.onSelectedToggled(),
                ),
                Expanded(child: ConfidenceBadge(confidence: contact.confidence)),
                IconButton(
                  tooltip: 'Open full editor',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: widget.onOpenEditor,
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: widget.onDeleted,
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameController,
                    onChanged: widget.onNameChanged,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      isDense: true,
                      prefixIcon: Icon(Icons.person_outline, size: 20),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _phoneController,
                    onChanged: widget.onPhoneChanged,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d+\s\-()]')),
                    ],
                    style: const TextStyle(
                      fontSize: 16,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    decoration: InputDecoration(
                      labelText: 'Phone number',
                      isDense: true,
                      prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                      errorText: contact.issues.contains(PairingIssue.invalidPhone)
                          ? 'Check this number'
                          : null,
                    ),
                  ),
                ],
              ),
            ),

            if (contact.issues.isNotEmpty) ...[
              const SizedBox(height: 10),
              _IssueChips(issues: contact.issues),
            ],

            const SizedBox(height: 10),
            _ExpiryRow(
              expiry: contact.expiry,
              onChanged: widget.onExpiryChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _IssueChips extends StatelessWidget {
  const _IssueChips({required this.issues});

  final Set<PairingIssue> issues;

  String _label(PairingIssue issue) => switch (issue) {
        PairingIssue.unmatchedName => 'No number found on this row',
        PairingIssue.unmatchedPhone => 'No name found on this row',
        PairingIssue.ambiguousPairing => 'Another name was a close match',
        PairingIssue.lowConfidence => 'Hard to read',
        PairingIssue.invalidPhone => 'Number looks incomplete',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final issue in issues)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _label(issue),
              style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
            ),
          ),
      ],
    );
  }
}

class _ExpiryRow extends StatelessWidget {
  const _ExpiryRow({required this.expiry, required this.onChanged});

  final ExpirySelection expiry;
  final ValueChanged<ExpirySelection> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isTemporary = expiry.isTemporary;

    return Row(
      children: [
        Icon(
          isTemporary ? Icons.timer_outlined : Icons.all_inclusive,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            isTemporary ? 'Temporary · ${expiry.option.label}' : 'Permanent',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ),
        TextButton(
          onPressed: () async {
            final result = await ExpiryPickerSheet.show(
              context,
              initial: expiry,
            );
            if (result != null) onChanged(result);
          },
          child: const Text('Change'),
        ),
      ],
    );
  }
}
