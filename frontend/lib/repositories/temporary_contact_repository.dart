import 'package:sqflite/sqflite.dart';

import '../core/errors/app_exceptions.dart' as errors;
import '../core/utils/redaction.dart';
import '../database/app_database.dart';
import '../models/temporary_contact.dart';

/// Persistence for the temporary-contact registry (§14).
///
/// All SQL lives here; widgets and services speak only [TemporaryContact].
class TemporaryContactRepository {
  TemporaryContactRepository(this._db);

  final AppDatabase _db;

  static const _tag = 'TempContactRepo';
  static const _table = TemporaryContact.table;

  Future<Database> get _database => _db.database;

  /// Registers a newly-created contact.
  ///
  /// Uses upsert semantics on `os_contact_id`: if the same OS contact is
  /// registered twice — a re-save after a failed cleanup, say — the existing
  /// row is replaced rather than duplicated (§16).
  Future<TemporaryContact> upsert(TemporaryContact contact) async {
    try {
      final db = await _database;
      final id = await db.insert(
        _table,
        contact.toRow()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return contact.copyWith(id: id);
    } catch (e, s) {
      throw _wrap('registering contact', e, s);
    }
  }

  /// Inserts many rows in one transaction so a partial batch cannot survive
  /// a crash (§16 "transactional where possible").
  Future<List<TemporaryContact>> upsertAll(
    List<TemporaryContact> contacts,
  ) async {
    if (contacts.isEmpty) return const [];
    try {
      final db = await _database;
      final saved = <TemporaryContact>[];
      await db.transaction((txn) async {
        for (final contact in contacts) {
          final id = await txn.insert(
            _table,
            contact.toRow()..remove('id'),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          saved.add(contact.copyWith(id: id));
        }
      });
      return saved;
    } catch (e, s) {
      throw _wrap('registering contacts', e, s);
    }
  }

  Future<List<TemporaryContact>> all() => _query();

  /// Rows the Temporary Contacts screen shows: everything not yet finished.
  Future<List<TemporaryContact>> active() => _query(
        where: 'status IN (?, ?)',
        whereArgs: [
          TemporaryContactStatus.active.name,
          TemporaryContactStatus.error.name,
        ],
        orderBy: 'expires_at IS NULL, expires_at ASC',
      );

  /// History: rows whose lifecycle has ended.
  Future<List<TemporaryContact>> finished() => _query(
        where: 'status IN (?, ?)',
        whereArgs: [
          TemporaryContactStatus.deleted.name,
          TemporaryContactStatus.missing.name,
        ],
        orderBy: 'last_checked_at DESC',
      );

  /// Rows eligible for automatic deletion at [now] (§15).
  ///
  /// The bound on `retry_count` stops a permanently-failing row from being
  /// retried forever.
  Future<List<TemporaryContact>> dueForCleanup(
    DateTime now, {
    int maxRetries = 5,
  }) =>
      _query(
        where: 'created_by_app = 1 '
            'AND status IN (?, ?) '
            'AND expires_at IS NOT NULL '
            'AND expires_at <= ? '
            'AND retry_count < ?',
        whereArgs: [
          TemporaryContactStatus.active.name,
          TemporaryContactStatus.error.name,
          now.toUtc().millisecondsSinceEpoch,
          maxRetries,
        ],
        orderBy: 'expires_at ASC',
      );

  Future<TemporaryContact?> findByOsContactId(String osContactId) async {
    final rows = await _query(
      where: 'os_contact_id = ?',
      whereArgs: [osContactId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<TemporaryContact?> findById(int id) async {
    final rows = await _query(where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Returns the comparison keys of every phone number this app has
  /// registered, used to spot our own prior saves during duplicate detection.
  Future<Set<String>> registeredPhones() async {
    final rows = await _query();
    return rows.map((r) => r.phone).toSet();
  }

  /// Applies a status transition.
  ///
  /// Terminal states are never overwritten, which is what makes running
  /// cleanup twice harmless (§16).
  Future<void> updateStatus(
    int id,
    TemporaryContactStatus status, {
    DateTime? checkedAt,
    int? retryCount,
  }) async {
    try {
      final db = await _database;
      await db.update(
        _table,
        {
          'status': status.name,
          'last_checked_at':
              (checkedAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
          'retry_count': ?retryCount,
        },
        // Guard clause: refuse to move a finished row back to an active state.
        where: 'id = ? AND status NOT IN (?, ?)',
        whereArgs: [
          id,
          TemporaryContactStatus.deleted.name,
          TemporaryContactStatus.missing.name,
        ],
      );
    } catch (e, s) {
      throw _wrap('updating contact status', e, s);
    }
  }

  /// Changes an expiry (extend, shorten, or make permanent) (§17).
  Future<void> updateExpiry(int id, DateTime? expiresAt) async {
    try {
      final db = await _database;
      await db.update(
        _table,
        {
          'expires_at': expiresAt?.toUtc().millisecondsSinceEpoch,
          // Re-arming an expired row returns it to the active pool.
          'status': TemporaryContactStatus.active.name,
          'retry_count': 0,
        },
        where: 'id = ? AND status NOT IN (?, ?)',
        whereArgs: [
          id,
          TemporaryContactStatus.deleted.name,
          TemporaryContactStatus.missing.name,
        ],
      );
    } catch (e, s) {
      throw _wrap('updating expiry', e, s);
    }
  }

  Future<void> incrementRetry(int id) async {
    try {
      final db = await _database;
      await db.rawUpdate(
        'UPDATE $_table SET retry_count = retry_count + 1, status = ? '
        'WHERE id = ?',
        [TemporaryContactStatus.error.name, id],
      );
    } catch (e, s) {
      throw _wrap('recording retry', e, s);
    }
  }

  /// Removes a registry row entirely. Used when the user converts a contact to
  /// permanent and no longer wants it tracked.
  Future<void> delete(int id) async {
    try {
      final db = await _database;
      await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    } catch (e, s) {
      throw _wrap('deleting registry row', e, s);
    }
  }

  /// Clears finished history rows older than [before].
  Future<int> purgeFinishedBefore(DateTime before) async {
    try {
      final db = await _database;
      return await db.delete(
        _table,
        where: 'status IN (?, ?) AND last_checked_at IS NOT NULL '
            'AND last_checked_at < ?',
        whereArgs: [
          TemporaryContactStatus.deleted.name,
          TemporaryContactStatus.missing.name,
          before.toUtc().millisecondsSinceEpoch,
        ],
      );
    } catch (e, s) {
      throw _wrap('purging history', e, s);
    }
  }

  Future<int> count() async {
    final db = await _database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM $_table');
    return (result.first['c'] as int?) ?? 0;
  }

  Future<List<TemporaryContact>> _query({
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    try {
      final db = await _database;
      final rows = await db.query(
        _table,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy ?? 'created_at DESC',
        limit: limit,
      );
      return rows.map(TemporaryContact.fromRow).toList(growable: false);
    } catch (e, s) {
      throw _wrap('reading registry', e, s);
    }
  }

  errors.DatabaseException _wrap(String action, Object e, StackTrace s) {
    AppLog.error(_tag, 'failure while $action', e, s);
    return errors.DatabaseException(
      'The local contact registry could not be updated.',
      cause: e,
      stackTrace: s,
    );
  }
}
