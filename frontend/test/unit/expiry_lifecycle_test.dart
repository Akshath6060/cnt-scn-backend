import 'package:contact_scanner/database/app_database.dart';
import 'package:contact_scanner/models/temporary_contact.dart';
import 'package:contact_scanner/repositories/temporary_contact_repository.dart';
import 'package:contact_scanner/services/contact_service.dart';
import 'package:contact_scanner/services/expiry_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../fixtures/fake_contacts_gateway.dart';

void main() {
  late AppDatabase database;
  late TemporaryContactRepository repository;
  late FakeContactsGateway gateway;
  late ContactService contacts;
  late ExpiryService expiry;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    database = AppDatabase(
      databaseName: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    repository = TemporaryContactRepository(database);
    gateway = FakeContactsGateway();
    contacts = ContactService(gateway: gateway);
    expiry = ExpiryService(repository: repository, contacts: contacts);
  });

  tearDown(() async => database.close());

  /// Registers a contact in both the fake phonebook and the registry.
  Future<TemporaryContact> register({
    required String name,
    required String phone,
    required Duration expiresIn,
  }) async {
    final osId = await contacts.create(name: name, phone: phone);
    return repository.upsert(
      TemporaryContact(
        id: null,
        osContactId: osId,
        name: name,
        phone: phone,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(expiresIn),
        status: TemporaryContactStatus.active,
      ),
    );
  }

  group('repository (§14)', () {
    test('round-trips a contact through SQLite', () async {
      final saved = await register(
        name: 'Anu',
        phone: '+919876543210',
        expiresIn: const Duration(hours: 1),
      );
      expect(saved.id, isNotNull);

      final loaded = await repository.findById(saved.id!);
      expect(loaded, isNotNull);
      expect(loaded!.name, 'Anu');
      expect(loaded.phone, '+919876543210');
      expect(loaded.status, TemporaryContactStatus.active);
      expect(loaded.osContactId, saved.osContactId);
      // Timestamps survive the UTC round-trip.
      expect(
        loaded.expiresAt!.difference(saved.expiresAt!).inSeconds.abs(),
        lessThan(2),
      );
    });

    test('re-registering the same OS contact updates rather than duplicates',
        () async {
      final first = await register(
        name: 'Anu',
        phone: '+919876543210',
        expiresIn: const Duration(hours: 1),
      );
      await repository.upsert(
        first.copyWith(name: 'Anu Sharma'),
      );
      expect(await repository.count(), 1);
      final loaded = await repository.findByOsContactId(first.osContactId);
      expect(loaded!.name, 'Anu Sharma');
    });

    test('dueForCleanup returns only expired active rows', () async {
      await register(
          name: 'Expired', phone: '+919000000001',
          expiresIn: const Duration(seconds: -10));
      await register(
          name: 'Future', phone: '+919000000002',
          expiresIn: const Duration(hours: 2));

      final due = await repository.dueForCleanup(DateTime.now());
      expect(due, hasLength(1));
      expect(due.single.name, 'Expired');
    });

    test('permanent rows are never due for cleanup', () async {
      final c = await register(
          name: 'Perm', phone: '+919000000003',
          expiresIn: const Duration(seconds: -10));
      await repository.updateExpiry(c.id!, null);

      final due = await repository.dueForCleanup(DateTime.now());
      expect(due, isEmpty);
    });
  });

  group('cleanup (§15)', () {
    test('deletes the expired contact from the phonebook', () async {
      final c = await register(
          name: 'Anu', phone: '+919876543210',
          expiresIn: const Duration(seconds: -1));
      expect(gateway.store.containsKey(c.osContactId), isTrue);

      final report = await expiry.runCleanup();

      expect(report.examined, 1);
      expect(report.deleted, 1);
      expect(gateway.store.containsKey(c.osContactId), isFalse);
      expect(
        (await repository.findById(c.id!))!.status,
        TemporaryContactStatus.deleted,
      );
    });

    test('leaves unexpired contacts alone', () async {
      final c = await register(
          name: 'Later', phone: '+919000000004',
          expiresIn: const Duration(hours: 5));
      final report = await expiry.runCleanup();

      expect(report.examined, 0);
      expect(gateway.store.containsKey(c.osContactId), isTrue);
    });

    test('deletes ONLY the registered OS contact, never by name (§13)',
        () async {
      // A user-created contact sharing the same name and number.
      final userOwned = await gateway.insert(name: 'Anu', phone: '+919876543210');

      final ours = await register(
          name: 'Anu', phone: '+919876543210',
          expiresIn: const Duration(seconds: -1));

      await expiry.runCleanup();

      // Ours is gone; the user's identical contact is untouched.
      expect(gateway.store.containsKey(ours.osContactId), isFalse);
      expect(gateway.store.containsKey(userOwned.id), isTrue);
    });

    test('marks a hand-deleted contact as missing, not error (§16)', () async {
      final c = await register(
          name: 'Gone', phone: '+919000000005',
          expiresIn: const Duration(seconds: -1));
      gateway.userDeletes(c.osContactId);

      final report = await expiry.runCleanup();
      expect(report.missing, 1);
      expect(report.deleted, 0);
      expect(
        (await repository.findById(c.id!))!.status,
        TemporaryContactStatus.missing,
      );
    });

    test('records a failure and retries on the next pass', () async {
      final c = await register(
          name: 'Stuck', phone: '+919000000006',
          expiresIn: const Duration(seconds: -1));
      gateway.failDeletionFor.add(c.osContactId);

      final first = await expiry.runCleanup();
      expect(first.failed, 1);

      var row = await repository.findById(c.id!);
      expect(row!.status, TemporaryContactStatus.error);
      expect(row.retryCount, 1);

      // Still eligible, so a later pass tries again.
      final second = await expiry.runCleanup();
      expect(second.examined, 1);
      row = await repository.findById(c.id!);
      expect(row!.retryCount, 2);
    });

    test('stops retrying after the retry budget is exhausted', () async {
      final c = await register(
          name: 'Hopeless', phone: '+919000000007',
          expiresIn: const Duration(seconds: -1));
      gateway.failDeletionFor.add(c.osContactId);

      for (var i = 0; i < 6; i++) {
        await expiry.runCleanup();
      }
      final row = await repository.findById(c.id!);
      expect(row!.retryCount, 5);

      // No longer selected for cleanup.
      expect(await repository.dueForCleanup(DateTime.now()), isEmpty);
    });
  });

  group('idempotency and crash safety (§16)', () {
    test('running cleanup twice is harmless', () async {
      final c = await register(
          name: 'Anu', phone: '+919876543210',
          expiresIn: const Duration(seconds: -1));

      final first = await expiry.runCleanup();
      final second = await expiry.runCleanup();

      expect(first.deleted, 1);
      // Second pass finds nothing left to do.
      expect(second.examined, 0);
      expect(second.deleted, 0);

      // And the phonebook was only ever asked to delete once.
      expect(gateway.deleteAttempts[c.osContactId], 1);
      expect(
        (await repository.findById(c.id!))!.status,
        TemporaryContactStatus.deleted,
      );
    });

    test('a terminal row can never be moved back to active', () async {
      final c = await register(
          name: 'Done', phone: '+919000000008',
          expiresIn: const Duration(seconds: -1));
      await expiry.runCleanup();

      // Attempt an illegal transition.
      await repository.updateStatus(c.id!, TemporaryContactStatus.active);
      expect(
        (await repository.findById(c.id!))!.status,
        TemporaryContactStatus.deleted,
      );
    });

    test('concurrent cleanup calls are coalesced into one pass', () async {
      final c = await register(
          name: 'Race', phone: '+919000000009',
          expiresIn: const Duration(seconds: -1));

      final results = await Future.wait([
        expiry.runCleanup(),
        expiry.runCleanup(),
        expiry.runCleanup(),
      ]);

      // Exactly one deletion attempt despite three concurrent triggers.
      expect(gateway.deleteAttempts[c.osContactId], 1);
      expect(results.map((r) => r.deleted).reduce((a, b) => a + b), 3 * 1);
    });
  });

  group('user actions (§17)', () {
    test('convert to permanent stops future deletion', () async {
      final c = await register(
          name: 'Keep', phone: '+919000000010',
          expiresIn: const Duration(seconds: -1));
      await expiry.convertToPermanent(c);

      final report = await expiry.runCleanup();
      expect(report.examined, 0);
      expect(gateway.store.containsKey(c.osContactId), isTrue);
      expect((await repository.findById(c.id!))!.isPermanent, isTrue);
    });

    test('extend expiry postpones deletion', () async {
      final c = await register(
          name: 'Later', phone: '+919000000011',
          expiresIn: const Duration(seconds: -1));
      await expiry.changeExpiry(c, DateTime.now().add(const Duration(days: 2)));

      final report = await expiry.runCleanup();
      expect(report.examined, 0);
      expect(gateway.store.containsKey(c.osContactId), isTrue);
    });

    test('delete now removes ahead of expiry', () async {
      final c = await register(
          name: 'Now', phone: '+919000000012',
          expiresIn: const Duration(hours: 10));

      final outcome = await expiry.deleteNow(c);
      expect(outcome, ContactDeletionOutcome.deleted);
      expect(gateway.store.containsKey(c.osContactId), isFalse);
    });

    test('reconcile flags contacts the user deleted early', () async {
      final c = await register(
          name: 'Vanished', phone: '+919000000013',
          expiresIn: const Duration(hours: 10));
      gateway.userDeletes(c.osContactId);

      final changed = await expiry.reconcile();
      expect(changed, 1);
      expect(
        (await repository.findById(c.id!))!.status,
        TemporaryContactStatus.missing,
      );
    });
  });
}
