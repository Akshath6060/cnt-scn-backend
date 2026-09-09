import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/temporary_contact.dart';
import '../../providers/app_providers.dart';
import '../../widgets/expiry_picker.dart';

/// Everything this app has written to the phonebook (§3).
///
/// The registry is the source of truth for "what did this app create?", which
/// is also what makes deletion safe: nothing outside this list is ever touched.
class SavedContactsScreen extends ConsumerStatefulWidget {
  const SavedContactsScreen({super.key});

  @override
  ConsumerState<SavedContactsScreen> createState() =>
      _SavedContactsScreenState();
}

class _SavedContactsScreenState extends ConsumerState<SavedContactsScreen> {
  late Future<List<TemporaryContact>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = ref.read(temporaryContactRepositoryProvider).all();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Saved Contacts')),
      body: FutureBuilder<List<TemporaryContact>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'The local record of saved contacts could not be read.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final contacts = snapshot.data ?? const <TemporaryContact>[];
          if (contacts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nothing saved yet. Scan a contact sheet to get started.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => setState(_load),
            child: ListView.separated(
              itemCount: contacts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final contact = contacts[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      contact.name.isEmpty
                          ? '?'
                          : contact.name.substring(0, 1).toUpperCase(),
                    ),
                  ),
                  title: Text(contact.name),
                  subtitle: Text(
                    '${contact.phone}\n'
                    '${contact.isPermanent ? 'Permanent' : formatExpiry(contact.expiresAt)}'
                    ' · ${contact.status.label}',
                    style: theme.textTheme.bodySmall,
                  ),
                  isThreeLine: true,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
