import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/redaction.dart';
import '../database/app_database.dart';
import '../platform/native_contacts/native_contacts_gateway.dart';
import '../repositories/temporary_contact_repository.dart';
import 'contact_service.dart';
import 'expiry_service.dart';

/// Entry point invoked by the OS scheduler in a **fresh isolate** (§15).
///
/// Nothing from the running app is available here, so the whole dependency
/// graph is rebuilt locally. The handler is deliberately defensive: it must
/// never throw, because an uncaught error would be reported to the platform
/// as a permanent task failure.
@pragma('vm:entry-point')
void backgroundCleanupDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != AppConstants.cleanupTaskName) return true;

    try {
      final database = AppDatabase();
      final repository = TemporaryContactRepository(database);
      final contacts = ContactService(gateway: const FlutterContactsGateway());
      final expiry = ExpiryService(repository: repository, contacts: contacts);

      final report = await expiry.runCleanup();
      AppLog.info('BackgroundCleanup', 'background pass: $report');

      await database.close();

      // Report success even when individual rows failed: those are retried on
      // their own schedule, and returning false would make the OS back off
      // the whole task (§15).
      return true;
    } catch (e, s) {
      AppLog.error('BackgroundCleanup', 'background pass failed', e, s);
      // Returning true avoids an exponential backoff that would delay the next
      // legitimate cleanup; the in-app triggers remain the reliable path.
      return true;
    }
  });
}

/// Registers and triggers OS-level expiry cleanup (§15).
///
/// Neither Android nor iOS guarantees punctual execution, which is exactly why
/// this is only *one* of five triggers. The others — launch, resume, opening
/// the temporary list, and saving new temporary contacts — are driven from the
/// app and are what make expiry feel reliable in practice.
class BackgroundCleanupService {
  BackgroundCleanupService({Workmanager? workmanager})
      : _workmanager = workmanager ?? Workmanager();

  final Workmanager _workmanager;

  static const _tag = 'BackgroundCleanup';
  bool _initialized = false;

  /// Whether the current platform supports OS-scheduled background work.
  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  /// Initialises the scheduler and registers the periodic task.
  ///
  /// Failure here is non-fatal: the app-driven triggers still run (§25).
  Future<void> initialize() async {
    if (_initialized || !isSupported) return;

    try {
      await _workmanager.initialize(backgroundCleanupDispatcher);
      _initialized = true;
      await _registerPeriodicTask();
    } catch (e, s) {
      AppLog.error(_tag, 'scheduler initialisation failed', e, s);
    }
  }

  Future<void> _registerPeriodicTask() async {
    try {
      await _workmanager.registerPeriodicTask(
        AppConstants.cleanupTaskUniqueName,
        AppConstants.cleanupTaskName,
        // 15 minutes is the platform minimum on Android; iOS treats it as a
        // hint and may run far less often.
        frequency: AppConstants.cleanupInterval,
        // Explicitly no network requirement — the whole app is offline (§2).
        constraints: Constraints(networkType: NetworkType.notRequired),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
      AppLog.info(_tag, 'periodic cleanup task registered');
    } catch (e, s) {
      AppLog.error(_tag, 'could not register periodic task', e, s);
    }
  }

  /// Requests a one-off cleanup soon — used after saving temporary contacts so
  /// a short expiry is honoured even if the app is closed immediately.
  Future<void> requestImmediateCleanup({Duration delay = Duration.zero}) async {
    if (!isSupported) return;
    try {
      await _workmanager.registerOneOffTask(
        '${AppConstants.cleanupTaskUniqueName}.oneoff.'
            '${DateTime.now().millisecondsSinceEpoch}',
        AppConstants.cleanupTaskName,
        initialDelay: delay,
        constraints: Constraints(networkType: NetworkType.notRequired),
      );
    } catch (e, s) {
      AppLog.error(_tag, 'could not schedule one-off cleanup', e, s);
    }
  }

  /// Cancels all scheduled work. Used when the registry becomes empty.
  Future<void> cancelAll() async {
    if (!isSupported) return;
    try {
      await _workmanager.cancelAll();
    } catch (e, s) {
      AppLog.error(_tag, 'could not cancel scheduled work', e, s);
    }
  }

  @visibleForTesting
  bool get isInitialized => _initialized;
}
