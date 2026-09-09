import 'package:contact_scanner/platform/native_contacts/native_contacts_gateway.dart';

/// In-memory stand-in for the device phonebook.
class FakeContactsGateway implements NativeContactsGateway {
  FakeContactsGateway({this.permissionGranted = true});

  bool permissionGranted;
  final Map<String, NativeContact> store = {};
  int _nextId = 1;

  /// Ids for which deletion should fail, to exercise the error path.
  final Set<String> failDeletionFor = {};

  /// Counts deletion attempts so idempotency can be asserted.
  final Map<String, int> deleteAttempts = {};

  @override
  Future<bool> requestPermission({bool readonly = false}) async =>
      permissionGranted;

  @override
  Future<bool> hasPermission({bool readonly = false}) async =>
      permissionGranted;

  @override
  Future<List<NativeContact>> fetchAll() async => store.values.toList();

  @override
  Future<NativeContact?> fetchById(String id) async => store[id];

  @override
  Future<NativeContact> insert({
    required String name,
    required String phone,
  }) async {
    final id = 'OS_CONTACT_${_nextId++}';
    final contact = NativeContact(id: id, displayName: name, phones: [phone]);
    store[id] = contact;
    return contact;
  }

  @override
  Future<void> update({required String id, String? name, String? phone}) async {
    final existing = store[id];
    if (existing == null) return;
    store[id] = NativeContact(
      id: id,
      displayName: name ?? existing.displayName,
      phones: phone != null ? [phone] : existing.phones,
    );
  }

  @override
  Future<void> deleteById(String id) async {
    deleteAttempts[id] = (deleteAttempts[id] ?? 0) + 1;
    if (failDeletionFor.contains(id)) {
      throw StateError('simulated deletion failure');
    }
    store.remove(id);
  }

  /// Simulates the user deleting a contact by hand.
  void userDeletes(String id) => store.remove(id);
}
