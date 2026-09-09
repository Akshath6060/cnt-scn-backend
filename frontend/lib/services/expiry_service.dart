import '../core/constants/app_constants.dart';
import '../core/utils/redaction.dart';
import '../models/temporary_contact.dart';
import '../repositories/temporary_contact_repository.dart';
import 'contact_service.dart';

/// Tally of one cleanup pass.
class CleanupReport {
  const CleanupReport({
    this.examined = 0,
    this.deleted = 0,
    this.missing = 0,
    this.failed = 0,
    this.skipped = 0,
    this.startedAt,
    this.finishedAt,
  });

  final int examined;
  final int deleted;
  final int missing;
  final int failed;

  /// Rows passed over because they had exhausted their retry budget.
  final int skipped;

  final DateTime? startedAt;
  final DateTime? finishedAt;

  bool get didWork => deleted > 0 || missing > 0 || failed > 0;

  CleanupReport copyWith({
    int? examined,
    int? deleted,
    int? missing,
    int? failed,
    int? skipped,
    DateTime? finishedAt,
  }) =>
      CleanupReport(
        examined: examined ?? this.examined,
        deleted: deleted ?? this.deleted,
        missing: missing ?? this.missing,
        failed: failed ?? this.failed,
        skipped: skipped ?? this.skipped,
        startedAt: startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
      );

  @override
  String toString() =>
      'CleanupReport(examined=$examined, deleted=$deleted, '
      'missing=$missing, failed=$failed, skipped=$skipped)';
}

/// Expiry lifecycle management (§15, §16).
///
/// The cleanup pass is deliberately built to be run often and from several
/// triggers at once:
///   * it is **idempotent** — a row that reaches a terminal state is never
///     revisited, and the repository refuses backwards transitions,
///   * it is **crash-safe** — each row is committed on its own, so an
///     interruption loses at most the row in flight,
///   * it is **re-entrant-safe** — a second concurrent call is coalesced onto
///     the first rather than double-deleting.
class ExpiryService {
  ExpiryService({
    required TemporaryContactRepository repository,
    required ContactService contacts,
  })  : _repository = repository,
        _contacts = contacts;

  final TemporaryContactRepository _repository;
  final ContactService _contacts;

  static const _tag = 'ExpiryService';

  Future<CleanupReport>? _inFlight;

  /// Runs a cleanup pass, coalescing concurrent callers.
  ///
  /// Several triggers fire this (§15): OS scheduling, app launch, app resume,
  /// opening the temporary-contact list, and saving new temporary contacts.
  /// Without coalescing, launch + resume could overlap on the same rows.
  Future<CleanupReport> runCleanup({DateTime? now}) {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = _runCleanup(now ?? DateTime.now());
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<CleanupReport> _runCleanup(DateTime now) async {
    final startedAt = DateTime.now();
    var report = CleanupReport(startedAt: startedAt);

    List<TemporaryContact> due;
    try {
      due = await _repository.dueForCleanup(
        now,
        maxRetries: AppConstants.maxCleanupRetries,
      );
    } catch (e, s) {
      AppLog.error(_tag, 'could not query due contacts', e, s);
      return report.copyWith(finishedAt: DateTime.now());
    }

    if (due.isEmpty) {
      return report.copyWith(finishedAt: DateTime.now());
    }

    AppLog.info(_tag, 'cleanup: ${due.length} contact(s) due');
    report = report.copyWith(examined: due.length);

    var deleted = 0, missing = 0, failed = 0;

    for (final contact in due) {
      final id = contact.id;
      if (id == null) continue;

      // Belt and braces: never touch a row this app did not create (§13).
      if (!contact.createdByApp) continue;

      try {
        final outcome = await _contacts.deleteByOsId(contact.osContactId);

        switch (outcome) {
          case ContactDeletionOutcome.deleted:
            await _repository.updateStatus(
              id,
              TemporaryContactStatus.deleted,
              checkedAt: DateTime.now(),
            );
            deleted++;

          case ContactDeletionOutcome.missing:
            // The user removed it first — record that, do not treat as error
            // (§16).
            await _repository.updateStatus(
              id,
              TemporaryContactStatus.missing,
              checkedAt: DateTime.now(),
            );
            missing++;

          case ContactDeletionOutcome.failed:
            await _repository.incrementRetry(id);
            failed++;
        }
      } catch (e, s) {
        // One bad row must not abort the pass.
        AppLog.error(_tag, 'cleanup failed for a contact', e, s);
        try {
          await _repository.incrementRetry(id);
        } catch (_) {
          // Registry unavailable; the next pass will retry from scratch.
        }
        failed++;
      }
    }

    final result = report.copyWith(
      deleted: deleted,
      missing: missing,
      failed: failed,
      finishedAt: DateTime.now(),
    );
    AppLog.info(_tag, 'cleanup finished: $result');
    return result;
  }

  /// Reconciles the registry against the phonebook without deleting anything.
  ///
  /// Detects contacts the user removed by hand before expiry and marks them
  /// `missing`, so the list the user sees matches reality (§16).
  Future<int> reconcile() async {
    var changed = 0;
    try {
      final active = await _repository.active();
      for (final contact in active) {
        final id = contact.id;
        if (id == null) continue;
        final stillExists = await _contacts.exists(contact.osContactId);
        if (!stillExists) {
          await _repository.updateStatus(
            id,
            TemporaryContactStatus.missing,
            checkedAt: DateTime.now(),
          );
          changed++;
        }
      }
    } catch (e, s) {
      AppLog.error(_tag, 'reconcile failed', e, s);
    }
    return changed;
  }

  /// Deletes one contact immediately, ahead of its expiry (§17).
  Future<ContactDeletionOutcome> deleteNow(TemporaryContact contact) async {
    final id = contact.id;
    final outcome = await _contacts.deleteByOsId(contact.osContactId);
    if (id == null) return outcome;

    switch (outcome) {
      case ContactDeletionOutcome.deleted:
        await _repository.updateStatus(id, TemporaryContactStatus.deleted);
      case ContactDeletionOutcome.missing:
        await _repository.updateStatus(id, TemporaryContactStatus.missing);
      case ContactDeletionOutcome.failed:
        await _repository.incrementRetry(id);
    }
    return outcome;
  }

  /// Extends or changes an expiry (§17).
  Future<void> changeExpiry(TemporaryContact contact, DateTime? expiresAt) async {
    final id = contact.id;
    if (id == null) return;
    await _repository.updateExpiry(id, expiresAt);
  }

  /// Converts a temporary contact to permanent: the phonebook entry stays,
  /// and the registry stops tracking it for deletion (§17).
  Future<void> convertToPermanent(TemporaryContact contact) async {
    final id = contact.id;
    if (id == null) return;
    await _repository.updateExpiry(id, null);
  }
}
