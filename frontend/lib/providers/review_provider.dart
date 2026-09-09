import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exceptions.dart';
import '../models/contact_candidate.dart';
import '../models/expiry_option.dart';
import '../models/extracted_contact.dart';
import '../models/processing_result.dart';
import '../models/temporary_contact.dart';
import '../services/contact_service.dart';
import '../services/duplicate_detection_service.dart';
import '../services/phone_number_parser.dart';
import 'app_providers.dart';
import 'temporary_contacts_provider.dart';

/// Summary shown after saving (§10).
@immutable
class SaveSummary {
  const SaveSummary({
    this.saved = 0,
    this.skipped = 0,
    this.updated = 0,
    this.failed = 0,
    this.temporaryRegistered = 0,
    this.failures = const [],
  });

  final int saved;
  final int skipped;
  final int updated;
  final int failed;
  final int temporaryRegistered;

  /// Masked descriptions of what failed — never raw contact data (§28).
  final List<String> failures;

  int get total => saved + skipped + updated + failed;
  bool get hasFailures => failed > 0;
}

/// State of the review screen (§10).
@immutable
class ReviewState {
  const ReviewState({
    this.contacts = const [],
    this.unmatchedNames = const [],
    this.unmatchedPhones = const [],
    this.duplicates = const [],
    this.usedMockRecognizer = false,
    this.isSaving = false,
    this.error,
    this.summary,
  });

  final List<ExtractedContact> contacts;

  /// Leftovers the user can pair manually (§9).
  final List<ContactCandidate> unmatchedNames;
  final List<ContactCandidate> unmatchedPhones;

  final List<DuplicateMatch> duplicates;
  final bool usedMockRecognizer;
  final bool isSaving;
  final AppException? error;
  final SaveSummary? summary;

  List<ExtractedContact> get selected =>
      contacts.where((c) => c.isSelected).toList(growable: false);

  int get selectedCount => selected.length;
  bool get allSelected => contacts.isNotEmpty && selectedCount == contacts.length;
  bool get canSave => selected.any((c) => c.isComplete);

  int get needsAttentionCount =>
      contacts.where((c) => c.needsAttention).length;

  bool get hasLeftovers =>
      unmatchedNames.isNotEmpty || unmatchedPhones.isNotEmpty;

  ReviewState copyWith({
    List<ExtractedContact>? contacts,
    List<ContactCandidate>? unmatchedNames,
    List<ContactCandidate>? unmatchedPhones,
    List<DuplicateMatch>? duplicates,
    bool? isSaving,
    AppException? error,
    bool clearError = false,
    SaveSummary? summary,
  }) =>
      ReviewState(
        contacts: contacts ?? this.contacts,
        unmatchedNames: unmatchedNames ?? this.unmatchedNames,
        unmatchedPhones: unmatchedPhones ?? this.unmatchedPhones,
        duplicates: duplicates ?? this.duplicates,
        usedMockRecognizer: usedMockRecognizer,
        isSaving: isSaving ?? this.isSaving,
        error: clearError ? null : (error ?? this.error),
        summary: summary ?? this.summary,
      );
}

/// Drives the review/edit screen and the save transaction (§10, §12, §13).
class ReviewNotifier extends StateNotifier<ReviewState> {
  ReviewNotifier({
    required ContactService contacts,
    required DuplicateDetectionService duplicates,
    required PhoneNumberParser phoneParser,
    required Future<void> Function(List<TemporaryContact>) registerTemporary,
  })  : _contacts = contacts,
        _duplicates = duplicates,
        _phoneParser = phoneParser,
        _registerTemporary = registerTemporary,
        super(const ReviewState());

  final ContactService _contacts;
  final DuplicateDetectionService _duplicates;
  final PhoneNumberParser _phoneParser;
  final Future<void> Function(List<TemporaryContact>) _registerTemporary;

  /// Seeds the screen from a completed pipeline run.
  void loadFrom(ContactExtractionResult result) {
    state = ReviewState(
      contacts: result.contacts,
      unmatchedNames: result.unmatchedNames,
      unmatchedPhones: result.unmatchedPhones,
      usedMockRecognizer: result.usedMockRecognizer,
    );
  }

  // ── Per-contact editing ──────────────────────────────────────────────────

  void editName(String id, String name) => _replace(
        id,
        (c) => c.copyWith(name: name, wasEditedByUser: true),
      );

  void editPhone(String id, String phone) => _replace(id, (c) {
        final parsed = _phoneParser.parse(phone);
        final issues = Set<PairingIssue>.from(c.issues)
          ..remove(PairingIssue.invalidPhone);
        if (!parsed.isValid && phone.trim().isNotEmpty) {
          issues.add(PairingIssue.invalidPhone);
        }
        return c.copyWith(
          phone: phone,
          parsedPhone: parsed,
          issues: issues,
          wasEditedByUser: true,
        );
      });

  void toggleSelected(String id) =>
      _replace(id, (c) => c.copyWith(isSelected: !c.isSelected));

  void setExpiry(String id, ExpirySelection expiry) =>
      _replace(id, (c) => c.copyWith(expiry: expiry));

  void remove(String id) => state = state.copyWith(
        contacts: state.contacts.where((c) => c.id != id).toList(),
      );

  /// Manually pairs a leftover name with a leftover number (§10).
  void pairManually(ContactCandidate name, ContactCandidate phone) {
    final contact = ExtractedContact(
      id: 'manual_${DateTime.now().microsecondsSinceEpoch}',
      name: name.text,
      phone: phone.phone?.isValid == true
          ? phone.phone!.normalizedValue
          : phone.text,
      // A human made this call, so it carries full confidence.
      confidence: 1.0,
      parsedPhone: phone.phone,
      nameCandidate: name,
      phoneCandidate: phone,
      wasEditedByUser: true,
    );

    state = state.copyWith(
      contacts: [...state.contacts, contact],
      unmatchedNames:
          state.unmatchedNames.where((c) => c != name).toList(growable: false),
      unmatchedPhones:
          state.unmatchedPhones.where((c) => c != phone).toList(growable: false),
    );
  }

  /// Promotes a leftover into a half-filled card the user can complete.
  void adoptUnmatched(ContactCandidate candidate) {
    final isPhone = candidate.isPhone;
    final contact = ExtractedContact(
      id: 'adopted_${DateTime.now().microsecondsSinceEpoch}',
      name: isPhone ? '' : candidate.text,
      phone: isPhone ? candidate.text : '',
      confidence: candidate.overallConfidence,
      parsedPhone: candidate.phone,
      issues: {
        isPhone ? PairingIssue.unmatchedPhone : PairingIssue.unmatchedName,
      },
      wasEditedByUser: true,
    );
    state = state.copyWith(
      contacts: [...state.contacts, contact],
      unmatchedNames: state.unmatchedNames
          .where((c) => c != candidate)
          .toList(growable: false),
      unmatchedPhones: state.unmatchedPhones
          .where((c) => c != candidate)
          .toList(growable: false),
    );
  }

  // ── Bulk actions (§34) ───────────────────────────────────────────────────

  void selectAll(bool selected) => state = state.copyWith(
        contacts: state.contacts
            .map((c) => c.copyWith(isSelected: selected))
            .toList(growable: false),
      );

  void setExpiryForSelected(ExpirySelection expiry) => state = state.copyWith(
        contacts: state.contacts
            .map((c) => c.isSelected ? c.copyWith(expiry: expiry) : c)
            .toList(growable: false),
      );

  void markSelectedTemporary(ExpiryOption option, {DateTime? customValue}) =>
      setExpiryForSelected(
        ExpirySelection(option: option, customValue: customValue),
      );

  void markSelectedPermanent() =>
      setExpiryForSelected(const ExpirySelection.permanent());

  // ── Duplicate detection (§12) ────────────────────────────────────────────

  /// Checks the selected contacts against the phonebook.
  ///
  /// Returns the matches so the UI can ask the user what to do; every match
  /// starts at [DuplicateResolution.skip], the safe default.
  Future<List<DuplicateMatch>> checkDuplicates() async {
    try {
      final existing = await _contacts.readAll();
      final found = _duplicates.findDuplicates(state.selected, existing);
      state = state.copyWith(duplicates: found, clearError: true);
      return found;
    } on AppException catch (e) {
      state = state.copyWith(error: e);
      return const [];
    }
  }

  void resolveDuplicate(String contactId, DuplicateResolution resolution) =>
      state = state.copyWith(
        duplicates: state.duplicates
            .map((d) => d.extracted.id == contactId
                ? d.copyWith(resolution: resolution)
                : d)
            .toList(growable: false),
      );

  void resolveAllDuplicates(DuplicateResolution resolution) =>
      state = state.copyWith(
        duplicates: state.duplicates
            .map((d) => d.copyWith(resolution: resolution))
            .toList(growable: false),
      );

  // ── Saving (§13) ─────────────────────────────────────────────────────────

  /// Writes the selected contacts to the phonebook and registers the
  /// temporary ones locally.
  ///
  /// Each contact is saved independently so one failure cannot lose the rest,
  /// and the registry write happens only for contacts that actually reached
  /// the phonebook (§13).
  Future<SaveSummary> save() async {
    if (state.isSaving) return const SaveSummary();
    state = state.copyWith(isSaving: true, clearError: true);

    var saved = 0, skipped = 0, updated = 0, failed = 0;
    final failures = <String>[];
    final toRegister = <TemporaryContact>[];

    try {
      await _contacts.ensurePermission();

      final resolutions = {
        for (final d in state.duplicates) d.extracted.id: d,
      };

      for (final contact in state.selected) {
        if (!contact.isComplete) {
          failed++;
          failures.add('An incomplete card was not saved.');
          continue;
        }

        final duplicate = resolutions[contact.id];
        if (duplicate != null) {
          switch (duplicate.resolution) {
            case DuplicateResolution.skip:
              skipped++;
              continue;
            case DuplicateResolution.updateExisting:
              try {
                await _contacts.updateExisting(
                  osContactId: duplicate.existing.id,
                  name: contact.name,
                  phone: contact.phoneForSaving,
                );
                updated++;
              } catch (_) {
                failed++;
                failures.add('An existing contact could not be updated.');
              }
              continue;
            case DuplicateResolution.createAnyway:
              break; // fall through to a normal create
          }
        }

        try {
          final osId = await _contacts.create(
            name: contact.name.trim(),
            phone: contact.phoneForSaving,
          );
          saved++;

          if (contact.isTemporary) {
            final expiresAt = contact.expiry.resolve(DateTime.now());
            if (expiresAt != null) {
              toRegister.add(
                TemporaryContact(
                  id: null,
                  osContactId: osId,
                  name: contact.name.trim(),
                  phone: contact.phoneForSaving,
                  createdAt: DateTime.now(),
                  expiresAt: expiresAt,
                  status: TemporaryContactStatus.active,
                ),
              );
            }
          }
        } on AppException {
          failed++;
          failures.add('A contact could not be saved to the phonebook.');
        }
      }

      if (toRegister.isNotEmpty) {
        await _registerTemporary(toRegister);
      }

      final summary = SaveSummary(
        saved: saved,
        skipped: skipped,
        updated: updated,
        failed: failed,
        temporaryRegistered: toRegister.length,
        failures: failures,
      );
      state = state.copyWith(isSaving: false, summary: summary);
      return summary;
    } on AppException catch (e) {
      state = state.copyWith(isSaving: false, error: e);
      rethrow;
    }
  }

  void _replace(String id, ExtractedContact Function(ExtractedContact) update) =>
      state = state.copyWith(
        contacts: state.contacts
            .map((c) => c.id == id ? update(c) : c)
            .toList(growable: false),
      );
}

final reviewProvider =
    StateNotifierProvider<ReviewNotifier, ReviewState>((ref) {
  final repository = ref.watch(temporaryContactRepositoryProvider);
  final cleanup = ref.watch(backgroundCleanupProvider);

  return ReviewNotifier(
    contacts: ref.watch(contactServiceProvider),
    duplicates: ref.watch(duplicateDetectionProvider),
    phoneParser: ref.watch(phoneNumberParserProvider),
    registerTemporary: (contacts) async {
      await repository.upsertAll(contacts);
      // Trigger 5: run cleanup when new temporary contacts are saved, and ask
      // the OS to check again soon in case the app is closed immediately (§15).
      await ref.read(expiryServiceProvider).runCleanup();
      await cleanup.requestImmediateCleanup(
        delay: const Duration(minutes: 15),
      );
      ref.invalidate(temporaryContactsProvider);
    },
  );
});
