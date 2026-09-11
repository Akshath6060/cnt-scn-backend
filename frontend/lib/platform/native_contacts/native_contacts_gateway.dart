import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;

/// A contact as this app cares about it, independent of the plugin's types.
class NativeContact {
  const NativeContact({
    required this.id,
    required this.displayName,
    required this.phones,
  });

  /// Stable OS identifier. This is the value persisted as `os_contact_id` and
  /// the *only* handle ever used for deletion (§13).
  final String id;

  final String displayName;
  final List<String> phones;
}

/// Thin seam over the platform contacts plugin.
///
/// Everything above this interface is testable without a device; the single
/// implementation that touches `flutter_contacts` is [FlutterContactsGateway].
abstract class NativeContactsGateway {
  /// Requests contacts access. [readonly] asks only for read permission.
  Future<bool> requestPermission({bool readonly = false});

  Future<bool> hasPermission({bool readonly = false});

  /// All contacts with their phone numbers.
  Future<List<NativeContact>> fetchAll();

  /// Fetches one contact, or `null` when it no longer exists.
  Future<NativeContact?> fetchById(String id);

  /// Creates a contact and returns it with its assigned OS id.
  Future<NativeContact> insert({required String name, required String phone});

  /// Replaces the phone numbers on an existing contact.
  Future<void> update({required String id, String? name, String? phone});

  /// Deletes strictly by OS id.
  Future<void> deleteById(String id);
}

/// `flutter_contacts`-backed implementation.
class FlutterContactsGateway implements NativeContactsGateway {
  const FlutterContactsGateway();

  static const _androidChannel = MethodChannel(
    'com.example.contact_scanner/contacts',
  );

  @override
  Future<bool> requestPermission({bool readonly = false}) =>
      fc.FlutterContacts.requestPermission(readonly: readonly);

  @override
  Future<bool> hasPermission({bool readonly = false}) async {
    // The plugin exposes no pure query, so this asks without a prompt where
    // the platform allows it and otherwise reports the request's outcome.
    return fc.FlutterContacts.requestPermission(readonly: readonly);
  }

  @override
  Future<List<NativeContact>> fetchAll() async {
    final contacts = await fc.FlutterContacts.getContacts(
      withProperties: true,
      // Photos are irrelevant here and dominate memory on a large phonebook.
      withPhoto: false,
      withThumbnail: false,
    );
    return contacts.map(_map).toList(growable: false);
  }

  @override
  Future<NativeContact?> fetchById(String id) async {
    final contact = await fc.FlutterContacts.getContact(
      id,
      withProperties: true,
      withPhoto: false,
      withThumbnail: false,
    );
    return contact == null ? null : _map(contact);
  }

  @override
  Future<NativeContact> insert({
    required String name,
    required String phone,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final id = await _androidChannel.invokeMethod<String>('insertContact', {
        'name': name,
        'phone': phone,
      });
      if (id == null || id.isEmpty) {
        throw PlatformException(
          code: 'INSERT_FAILED',
          message: 'The contacts provider returned no contact ID.',
        );
      }
      return NativeContact(id: id, displayName: name, phones: [phone]);
    }

    final contact = fc.Contact()
      ..name.first = name
      ..phones = [fc.Phone(phone)];
    final inserted = await fc.FlutterContacts.insertContact(contact);
    return _map(inserted);
  }

  @override
  Future<void> update({required String id, String? name, String? phone}) async {
    final existing = await fc.FlutterContacts.getContact(
      id,
      withProperties: true,
    );
    if (existing == null) return;
    if (name != null && name.isNotEmpty) existing.name.first = name;
    if (phone != null && phone.isNotEmpty) {
      existing.phones = [fc.Phone(phone)];
    }
    await fc.FlutterContacts.updateContact(existing);
  }

  @override
  Future<void> deleteById(String id) async {
    // Resolve first so we delete exactly the record that id names, never a
    // name match (§13).
    final existing = await fc.FlutterContacts.getContact(
      id,
      withProperties: false,
    );
    if (existing == null) return;
    await fc.FlutterContacts.deleteContact(existing);
  }

  NativeContact _map(fc.Contact contact) => NativeContact(
    id: contact.id,
    displayName: contact.displayName,
    phones: contact.phones.map((p) => p.number).toList(growable: false),
  );
}
