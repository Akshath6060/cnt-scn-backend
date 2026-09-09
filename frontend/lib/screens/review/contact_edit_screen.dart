import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/expiry_option.dart';
import '../../models/extracted_contact.dart';
import '../../services/phone_number_parser.dart';
import '../../widgets/confidence_badge.dart';
import '../../widgets/expiry_picker.dart';

/// Full-screen editor for a single contact (§3 screen 6).
///
/// The review list handles quick inline edits; this screen is for the cases
/// that need room — a badly-read number, or checking exactly what the parser
/// made of it.
class ContactEditScreen extends StatefulWidget {
  const ContactEditScreen({
    super.key,
    required this.contact,
    this.phoneParser = const PhoneNumberParser(),
  });

  final ExtractedContact contact;
  final PhoneNumberParser phoneParser;

  /// Returns the edited contact, or `null` if cancelled.
  static Future<ExtractedContact?> open(
    BuildContext context,
    ExtractedContact contact,
  ) =>
      Navigator.of(context).push<ExtractedContact>(
        MaterialPageRoute(
          builder: (_) => ContactEditScreen(contact: contact),
        ),
      );

  @override
  State<ContactEditScreen> createState() => _ContactEditScreenState();
}

class _ContactEditScreenState extends State<ContactEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.contact.name);
  late final TextEditingController _phone =
      TextEditingController(text: widget.contact.phone);
  late ExpirySelection _expiry = widget.contact.expiry;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = widget.phoneParser.parse(_phone.text);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit contact'),
        actions: [
          TextButton(
            onPressed: _name.text.trim().isEmpty || _phone.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(
                      widget.contact.copyWith(
                        name: _name.text.trim(),
                        phone: _phone.text.trim(),
                        parsedPhone: parsed,
                        expiry: _expiry,
                        wasEditedByUser: true,
                      ),
                    ),
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ConfidenceBadge(confidence: widget.contact.confidence),
          const SizedBox(height: 20),

          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() {}),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d+\s\-()]')),
            ],
            decoration: InputDecoration(
              labelText: 'Phone number',
              prefixIcon: const Icon(Icons.phone_outlined),
              helperText: parsed.isValid
                  ? 'Will be saved as ${parsed.normalizedValue}'
                  : 'This does not look like a complete number yet',
            ),
          ),

          if (parsed.wasCorrected) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Automatic corrections applied',
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      parsed.appliedOcrCorrections.join(', '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _expiry.isTemporary ? Icons.timer_outlined : Icons.all_inclusive,
            ),
            title: const Text('Expiry'),
            subtitle: Text(
              _expiry.isTemporary ? _expiry.option.label : 'Permanent',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final selection =
                  await ExpiryPickerSheet.show(context, initial: _expiry);
              if (selection != null) setState(() => _expiry = selection);
            },
          ),
        ],
      ),
    );
  }
}
