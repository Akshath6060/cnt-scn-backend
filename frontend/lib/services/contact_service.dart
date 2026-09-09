import '../core/errors/app_exceptions.dart';
import '../core/utils/redaction.dart';
import '../models/extracted_contact.dart';
import '../platform/native_contacts/native_contacts_gateway.dart';
import 'phone_number_parser.dart';

/// Outcome of attempting to remove one OS contact.
enum ContactDeletionOutcome {
  /// The contact existed and was removed by us.
  deleted,

  /// The contact was already gone — the user most likely deleted it (§16).
  missing,

  /// Deletion was attempted and failed; safe to retry later.
  failed,
}

/// Result of saving one reviewed contact.
class ContactSaveOutcome {
  const ContactSaveOutcome({
    required this.contact,
    this.osContactId,
    this.skipped = false,
    this.error,
  });

  final ExtractedContact contact;

  /// Present when the contact reached the phonebook.
  final String? osContactId;

  /// True when the user chose to skip a duplicate (§12).
  final bool skipped;

  final AppException? error;

  bool get isSuccess => osContactId != null;
}

/// Reads and writes the device phonebook (§13).
///
/// Permission is requested only at the moment it is genuinely needed (§27).
class ContactService {
  ContactService({
    required NativeContactsGateway gateway,
    this.phoneParser = const PhoneNumberParser(),
  }) : _gateway = gateway;

  final NativeContactsGateway _gateway;
  final PhoneNumberParser phoneParser;

  static const _tag = 'ContactService';

  /// Requests contacts permission, throwing a typed error when refused.
  Future<void> ensurePermission({bool readonly = false}) async {
    final granted = await _gateway.requestPermission(readonly: readonly);
    if (!granted) throw ContactsException.permissionDenied;
  }

  /// Reads the phonebook. Used for duplicate detection (§12).
  Future<List<NativeContact>> readAll() async {
    await ensurePermission(readonly: true);
    try {
      return await _gateway.fetchAll();
    } catch (e, s) {
      AppLog.error(_tag, 'failed to read contacts', e, s);
      throw ContactsException(
        AppErrorCode.contactReadFailed,
        'Your contacts could not be read on this device.',
        cause: e,
        stackTrace: s,
      );
    }
  }

  /// Creates one contact and returns its OS identifier.
  Future<String> create({required String name, required String phone}) async {
    try {
      final created = await _gateway.insert(name: name, phone: phone);
      if (created.id.isEmpty) throw ContactsException.createFailed;
      AppLog.info(_tag, 'created contact ${maskName(name)}');
      return created.id;
    } on AppException {
      rethrow;
    } catch (e, s) {
      AppLog.error(_tag, 'failed to create contact', e, s);
      throw ContactsException(
        AppErrorCode.contactCreateFailed,
        ContactsException.createFailed.userMessage,
        cause: e,
        stackTrace: s,
      );
    }
  }

  /// Updates an existing contact, used by the "Update Existing" duplicate
  /// resolution (§12).
  Future<void> updateExisting({
    required String osContactId,
    String? name,
    String? phone,
  }) async {
    try {
      await _gateway.update(id: osContactId, name: name, phone: phone);
    } catch (e, s) {
      AppLog.error(_tag, 'failed to update contact', e, s);
      throw ContactsException(
        AppErrorCode.contactCreateFailed,
        'The existing contact could not be updated.',
        cause: e,
        stackTrace: s,
      );
    }
  }

  /// Whether the OS still holds a contact with this id.
  Future<bool> exists(String osContactId) async {
    try {
      return await _gateway.fetchById(osContactId) != null;
    } catch (e, s) {
      AppLog.error(_tag, 'existence check failed', e, s);
      // Unknown is not the same as absent: report "still there" so cleanup
      // retries rather than marking a live contact as missing.
      return true;
    }
  }

  /// Deletes the contact identified by [osContactId] — and nothing else.
  ///
  /// This is the only deletion path in the app. It never matches on name or
  /// phone number, which is what prevents a user-created contact from being
  /// removed by accident (§13).
  Future<ContactDeletionOutcome> deleteByOsId(String osContactId) async {
    if (osContactId.trim().isEmpty) return ContactDeletionOutcome.failed;

    try {
      final existing = await _gateway.fetchById(osContactId);
      if (existing == null) {
        // Already gone: idempotent success for cleanup purposes (§16).
        return ContactDeletionOutcome.missing;
      }

      await _gateway.deleteById(osContactId);

      // Verify: a silent no-op would otherwise be recorded as a deletion.
      final stillThere = await _gateway.fetchById(osContactId);
      if (stillThere != null) {
        AppLog.warn(_tag, 'contact survived deletion attempt');
        return ContactDeletionOutcome.failed;
      }
      return ContactDeletionOutcome.deleted;
    } catch (e, s) {
      AppLog.error(_tag, 'deletion failed', e, s);
      return ContactDeletionOutcome.failed;
    }
  }
}
