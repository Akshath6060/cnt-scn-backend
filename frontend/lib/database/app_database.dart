import 'package:sqflite/sqflite.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exceptions.dart' as errors;
import '../core/utils/redaction.dart';
import '../models/temporary_contact.dart';

/// Opens and migrates the local SQLite database (§14).
///
/// This is the only place that knows about schema and connection lifetime;
/// repositories take a [Database] and UI code never sees either.
class AppDatabase {
  AppDatabase({this.databaseName = AppConstants.databaseName, this.factory});

  final String databaseName;

  /// Injection point for tests, which supply the FFI factory.
  final DatabaseFactory? factory;

  Database? _database;
  Future<Database>? _opening;

  static const _tag = 'AppDatabase';

  /// Returns the open database, opening it on first use.
  Future<Database> get database async {
    final existing = _database;
    if (existing != null && existing.isOpen) return existing;
    return _opening ??= _open();
  }

  Future<Database> _open() async {
    try {
      final options = OpenDatabaseOptions(
        version: AppConstants.databaseVersion,
        onConfigure: (db) async {
          // Enforced so a future child table cannot orphan rows.
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgrade,
      );

      final db = factory != null
          ? await factory!.openDatabase(databaseName, options: options)
          : await openDatabase(
              databaseName,
              version: options.version,
              onConfigure: options.onConfigure,
              onCreate: options.onCreate,
              onUpgrade: options.onUpgrade,
            );

      _database = db;
      return db;
    } catch (e, s) {
      _opening = null;
      AppLog.error(_tag, 'failed to open database', e, s);
      throw errors.DatabaseException(
        errors.DatabaseException.generic.userMessage,
        cause: e,
        stackTrace: s,
      );
    }
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ${TemporaryContact.table} (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        os_contact_id   TEXT    NOT NULL,
        name            TEXT    NOT NULL,
        phone           TEXT    NOT NULL,
        created_at      INTEGER NOT NULL,
        expires_at      INTEGER,
        status          TEXT    NOT NULL,
        created_by_app  INTEGER NOT NULL DEFAULT 1,
        last_checked_at INTEGER,
        retry_count     INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // One registry row per OS contact: re-registering the same contact must
    // update rather than duplicate, which is what keeps cleanup idempotent
    // (§16).
    await db.execute(
      'CREATE UNIQUE INDEX idx_temp_os_contact_id '
      'ON ${TemporaryContact.table}(os_contact_id)',
    );

    // The cleanup worker's hot query is "active rows already past expiry".
    await db.execute(
      'CREATE INDEX idx_temp_status_expiry '
      'ON ${TemporaryContact.table}(status, expires_at)',
    );
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    // Version 1 is the initial schema; migrations are added here as the
    // schema evolves. Each step must be individually reversible-safe.
    AppLog.info(_tag, 'migrating database $oldVersion -> $newVersion');
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    _opening = null;
    if (db != null && db.isOpen) await db.close();
  }
}
