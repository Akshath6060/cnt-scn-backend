import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exceptions.dart';
import '../models/temporary_contact.dart';
import '../repositories/temporary_contact_repository.dart';
import '../services/contact_service.dart';
import '../services/expiry_service.dart';
import 'app_providers.dart';

/// What the Temporary Contacts screen renders (§17).
@immutable
class TemporaryContactsState {
  const TemporaryContactsState({
    this.active = const [],
    this.finished = const [],
    this.isLoading = true,
    this.error,
  });

  final List<TemporaryContact> active;
  final List<TemporaryContact> finished;
  final bool isLoading;
  final AppException? error;

  bool get isEmpty => active.isEmpty && finished.isEmpty;

  TemporaryContactsState copyWith({
    List<TemporaryContact>? active,
    List<TemporaryContact>? finished,
    bool? isLoading,
    AppException? error,
    bool clearError = false,
  }) => TemporaryContactsState(
    active: active ?? this.active,
    finished: finished ?? this.finished,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Owns the temporary-contact list and the user actions on it (§17).
///
/// Cleanup is run *before* the list is read, so what the user sees already
/// reflects any expiry that came due while the app was closed (§15 trigger 4).
class TemporaryContactsNotifier extends StateNotifier<TemporaryContactsState> {
  TemporaryContactsNotifier({
    required TemporaryContactRepository repository,
    required ExpiryService expiry,
  }) : _repository = repository,
       _expiry = expiry,
       super(const TemporaryContactsState()) {
    refresh();
  }

  final TemporaryContactRepository _repository;
  final ExpiryService _expiry;

  /// Runs cleanup, then reloads. Safe to call repeatedly.
  Future<void> refresh({bool runCleanup = true}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      if (runCleanup) {
        await _expiry.runCleanup();
        if (!mounted) return;
      }
      final active = await _repository.active();
      if (!mounted) return;
      final finished = await _repository.finished();
      if (!mounted) return;
      state = TemporaryContactsState(
        active: active,
        finished: finished,
        isLoading: false,
      );
    } on AppException catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e);
    } catch (e, s) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: DatabaseException(
          DatabaseException.generic.userMessage,
          cause: e,
          stackTrace: s,
        ),
      );
    }
  }

  /// Keeps the phonebook entry and stops tracking it for deletion (§17).
  Future<void> convertToPermanent(TemporaryContact contact) async {
    await _expiry.convertToPermanent(contact);
    await refresh(runCleanup: false);
  }

  /// Deletes ahead of schedule (§17).
  Future<ContactDeletionOutcome> deleteNow(TemporaryContact contact) async {
    final outcome = await _expiry.deleteNow(contact);
    await refresh(runCleanup: false);
    return outcome;
  }

  /// Extends by [extension] from the current expiry, or from now when the
  /// contact has already lapsed.
  Future<void> extend(TemporaryContact contact, Duration extension) async {
    final base = contact.expiresAt ?? DateTime.now();
    final from = base.isBefore(DateTime.now()) ? DateTime.now() : base;
    await _expiry.changeExpiry(contact, from.add(extension));
    await refresh(runCleanup: false);
  }

  /// Sets an absolute expiry (§17).
  Future<void> changeExpiry(
    TemporaryContact contact,
    DateTime? expiresAt,
  ) async {
    await _expiry.changeExpiry(contact, expiresAt);
    await refresh(runCleanup: false);
  }

  /// Clears finished history older than a week.
  Future<void> clearHistory() async {
    await _repository.purgeFinishedBefore(
      DateTime.now().subtract(const Duration(days: 7)),
    );
    await refresh(runCleanup: false);
  }
}

final temporaryContactsProvider =
    StateNotifierProvider<TemporaryContactsNotifier, TemporaryContactsState>(
      (ref) => TemporaryContactsNotifier(
        repository: ref.watch(temporaryContactRepositoryProvider),
        expiry: ref.watch(expiryServiceProvider),
      ),
    );
