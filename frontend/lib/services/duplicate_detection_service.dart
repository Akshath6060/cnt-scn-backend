import '../models/extracted_contact.dart';
import '../platform/native_contacts/native_contacts_gateway.dart';
import 'phone_number_parser.dart';

/// How an extracted contact matched an existing phonebook entry (§12).
enum DuplicateMatchType {
  /// The stored string is character-for-character identical.
  exactPhone,

  /// Same digits after stripping separators.
  normalizedPhone,

  /// Same subscriber number written with a different country-code form,
  /// e.g. `+919876543210` vs `09876543210`.
  countryCodeVariant,
}

/// What to do about a detected duplicate (§12).
///
/// [skip] is the default because creating a second copy of a number the user
/// already has is the one outcome they cannot easily undo in bulk.
enum DuplicateResolution { skip, updateExisting, createAnyway }

/// A detected collision between an extracted contact and the phonebook.
class DuplicateMatch {
  const DuplicateMatch({
    required this.extracted,
    required this.existing,
    required this.matchType,
    required this.matchedPhone,
    this.resolution = DuplicateResolution.skip,
  });

  final ExtractedContact extracted;
  final NativeContact existing;
  final DuplicateMatchType matchType;

  /// The phonebook number that matched.
  final String matchedPhone;

  final DuplicateResolution resolution;

  String get description => switch (matchType) {
        DuplicateMatchType.exactPhone => 'Already saved with this number',
        DuplicateMatchType.normalizedPhone =>
          'Already saved with the same number',
        DuplicateMatchType.countryCodeVariant =>
          'Already saved in a different format',
      };

  DuplicateMatch copyWith({DuplicateResolution? resolution}) => DuplicateMatch(
        extracted: extracted,
        existing: existing,
        matchType: matchType,
        matchedPhone: matchedPhone,
        resolution: resolution ?? this.resolution,
      );
}

/// Compares extracted contacts against the phonebook before saving (§12).
class DuplicateDetectionService {
  const DuplicateDetectionService({
    this.phoneParser = const PhoneNumberParser(),
  });

  final PhoneNumberParser phoneParser;

  /// Finds duplicates of [contacts] among [existing].
  ///
  /// Matching is done on the last-10-digit comparison key, so all the
  /// formatting variants §12 lists collapse onto one another.
  List<DuplicateMatch> findDuplicates(
    List<ExtractedContact> contacts,
    List<NativeContact> existing,
  ) {
    if (contacts.isEmpty || existing.isEmpty) return const [];

    // Index the phonebook once: contacts can number in the thousands and the
    // review screen may hold dozens of rows.
    final index = <String, List<(NativeContact, String)>>{};
    for (final contact in existing) {
      for (final phone in contact.phones) {
        final key = phoneParser.parse(phone).comparisonKey;
        if (key.isEmpty) continue;
        (index[key] ??= []).add((contact, phone));
      }
    }

    final matches = <DuplicateMatch>[];
    for (final candidate in contacts) {
      final parsed = phoneParser.parse(candidate.phoneForSaving);
      final key = parsed.comparisonKey;
      if (key.isEmpty) continue;

      final hits = index[key];
      if (hits == null || hits.isEmpty) continue;

      final (existingContact, existingPhone) = hits.first;
      matches.add(
        DuplicateMatch(
          extracted: candidate,
          existing: existingContact,
          matchedPhone: existingPhone,
          matchType: _classify(candidate.phoneForSaving, existingPhone),
        ),
      );
    }
    return matches;
  }

  DuplicateMatchType _classify(String candidate, String existing) {
    if (candidate == existing) return DuplicateMatchType.exactPhone;

    final a = candidate.replaceAll(RegExp(r'\D'), '');
    final b = existing.replaceAll(RegExp(r'\D'), '');
    if (a == b) return DuplicateMatchType.normalizedPhone;

    // Same subscriber digits, different country-code presentation.
    return DuplicateMatchType.countryCodeVariant;
  }
}
