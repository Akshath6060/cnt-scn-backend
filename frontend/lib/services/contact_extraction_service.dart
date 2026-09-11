import '../models/contact_candidate.dart';
import '../models/entity_type.dart';
import '../models/recognized_text.dart';
import 'phone_number_parser.dart';

/// Turns unstructured recognised strings into classified entities (§8).
///
/// Entirely rule-based and offline. No LLM, no NLP service, no word list
/// downloads. The rules are ordered from most to least certain so that a
/// confident phone match is never re-litigated as a name.
class ContactExtractionService {
  const ContactExtractionService({
    this.phoneParser = const PhoneNumberParser(),
  });

  final PhoneNumberParser phoneParser;

  // ── Recognisers for the classes we deliberately ignore (§8.5) ────────────

  static final RegExp _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
  static final RegExp _emailish = RegExp(
    r'@|\bgmail\b|\byahoo\b|\.com\b',
    caseSensitive: false,
  );

  /// Leading list markers: "1.", "2)", "03 -", "#4".
  static final RegExp _leadingSerial = RegExp(
    r'^\s*[#(\[]?\s*\d{1,3}\s*[.)\]:\-]\s+',
  );

  /// A bare serial or page number occupying the whole fragment.
  static final RegExp _bareSerial = RegExp(
    r'^\s*[#(\[]?\s*\d{1,3}\s*[.)\]]?\s*$',
  );

  static final RegExp _pageMarker = RegExp(
    r'^\s*(page|pg|p)\.?\s*\d+\s*$',
    caseSensitive: false,
  );

  static const List<String> _organizationKeywords = [
    'college',
    'university',
    'institute',
    'school',
    'academy',
    'dept',
    'department',
    'ltd',
    'pvt',
    'inc',
    'corp',
    'company',
    'society',
    'hospital',
    'clinic',
    'foundation',
    'trust',
    'branch',
    'office',
  ];

  static const List<String> _addressKeywords = [
    'road',
    'street',
    'st.',
    'lane',
    'nagar',
    'colony',
    'sector',
    'block',
    'floor',
    'flat',
    'apt',
    'apartment',
    'house',
    'plot',
    'near',
    'opp',
    'district',
    'pincode',
    'pin',
    'po box',
    'p.o',
  ];

  static const List<String> _headingKeywords = [
    'name',
    'phone',
    'mobile',
    'number',
    'no.',
    'contact',
    'sr',
    'sl',
    'serial',
    'list',
    'details',
    'email',
    'address',
    'signature',
    'date',
  ];

  // ── Public API ────────────────────────────────────────────────────────────

  /// Classifies every recognised fragment.
  ///
  /// Nothing is dropped: fragments we intend to ignore are returned with an
  /// ignorable [EntityType] so spatial analysis can still use their position
  /// (§8.5), and the review screen can show what was skipped.
  List<ContactCandidate> classify(List<RecognizedText> fragments) {
    final first = fragments
        .where((f) => !f.isEmpty)
        .map(_classifyOne)
        .toList(growable: false);

    return _refineWithRowContext(first);
  }

  /// Convenience: only the entries that can become contact fields.
  List<ContactCandidate> contactFields(List<ContactCandidate> all) =>
      all.where((c) => c.entityType.isContactField).toList(growable: false);

  // ── Stage 1: context-free classification ─────────────────────────────────

  ContactCandidate _classifyOne(RecognizedText fragment) {
    final raw = fragment.text.trim();
    final cleaned = _stripListMarker(raw);

    // 1. Phone — highest precedence, because the parser's gate is strict.
    if (phoneParser.looksLikePhone(cleaned) ||
        _looksLikeDamagedPhone(cleaned)) {
      final parsed = phoneParser.parse(cleaned);
      // A phone-shaped field that fails validation is still a phone; the user
      // repairs it on review rather than losing it (§9).
      return ContactCandidate(
        source: fragment,
        entityType: EntityType.phone,
        classificationConfidence: parsed.isValid ? parsed.confidence : 0.45,
        phone: parsed,
        normalizedText: cleaned,
      );
    }

    // 2. Email.
    if (_email.hasMatch(cleaned) || _emailish.hasMatch(cleaned)) {
      return _ignorable(fragment, EntityType.email, cleaned, 0.9);
    }

    // 3. Structural noise.
    if (_pageMarker.hasMatch(cleaned) || _bareSerial.hasMatch(raw)) {
      return _ignorable(fragment, EntityType.serialNumber, cleaned, 0.85);
    }

    final lower = cleaned.toLowerCase();

    // 4. Column headings — short, and exactly a heading word.
    if (_isHeading(lower)) {
      return _ignorable(fragment, EntityType.heading, cleaned, 0.8);
    }

    // 5. Address / organisation by keyword.
    if (_containsKeyword(lower, _addressKeywords)) {
      return _ignorable(fragment, EntityType.address, cleaned, 0.7);
    }
    if (_containsKeyword(lower, _organizationKeywords)) {
      return _ignorable(fragment, EntityType.organization, cleaned, 0.7);
    }

    // 6. Name candidate.
    final nameScore = scoreAsName(cleaned, fragment.confidence);
    if (nameScore > 0) {
      return ContactCandidate(
        source: fragment,
        entityType: EntityType.name,
        classificationConfidence: nameScore,
        normalizedText: _tidyName(cleaned),
      );
    }

    return ContactCandidate(
      source: fragment,
      entityType: EntityType.unknown,
      classificationConfidence: 0.2,
      normalizedText: cleaned,
    );
  }

  /// Keeps a digit-heavy OCR result visible when one or two digits were read
  /// as unsupported letters. It is intentionally returned as an invalid,
  /// low-confidence phone candidate so the user can repair it; no guessed
  /// number is ever saved automatically.
  bool _looksLikeDamagedPhone(String value) {
    final compact = value.replaceAll(RegExp(r'[\s\-+()./\\]'), '');
    if (compact.length < 7 || compact.length > 16) return false;

    final digits = RegExp(r'\d').allMatches(compact).length;
    final letters = RegExp(r'[A-Za-z]').allMatches(compact).length;
    final unsupported = compact.length - digits - letters;
    return unsupported == 0 && digits >= 5 && letters <= 3;
  }

  /// Heuristic name score in [0, 1]; 0 means "not a name" (§8.4).
  ///
  /// Signals: alphabetic ratio, length, word count, capitalisation, and the
  /// recogniser's own confidence.
  double scoreAsName(String value, double ocrConfidence) {
    final text = value.trim();
    if (text.isEmpty) return 0;

    final letters = RegExp(r'[A-Za-z]').allMatches(text).length;
    final digits = RegExp(r'\d').allMatches(text).length;
    final total = text.replaceAll(RegExp(r'\s'), '').length;
    if (total == 0) return 0;

    final alphaRatio = letters / total;

    // Names are overwhelmingly alphabetic.
    if (alphaRatio < 0.6) return 0;
    // More than two digits means it is not a personal name.
    if (digits > 2) return 0;
    if (letters < 2) return 0;
    if (text.length > 48) return 0;

    var score = 0.35;
    score += alphaRatio * 0.30;

    // Typical given/full-name length.
    if (text.length >= 3 && text.length <= 28) score += 0.12;

    // One to four words.
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (words >= 1 && words <= 4) score += 0.08;

    // Leading capital on the first word is a mild positive.
    if (RegExp(r'^[A-Z]').hasMatch(text)) score += 0.07;

    // ALL CAPS long strings read more like headings than names.
    if (text.length > 6 && text == text.toUpperCase()) score -= 0.10;

    // Fold in how well the recogniser actually read it.
    score = score * 0.75 + ocrConfidence * 0.25;

    return score.clamp(0.0, 0.98);
  }

  // ── Stage 2: row-aware refinement (§8.4 "proximity to phone number") ─────

  /// Boosts name confidence for fragments sharing a row with a phone number,
  /// and demotes lone `unknown` fragments that sit on a phone row.
  List<ContactCandidate> _refineWithRowContext(List<ContactCandidate> input) {
    final phones = input.where((c) => c.isPhone).toList();
    if (phones.isEmpty) return input;

    final rowTolerance = _medianHeight(input) * 0.6;

    return input
        .map((candidate) {
          if (candidate.isPhone) return candidate;

          final sharesRow = phones.any(
            (p) =>
                (p.box.centerY - candidate.box.centerY).abs() <= rowTolerance ||
                p.box.verticalOverlapRatio(candidate.box) >= 0.5,
          );

          if (!sharesRow) return candidate;

          // An unclassified fragment on a phone row is very likely the name.
          if (candidate.entityType == EntityType.unknown) {
            final score = scoreAsName(candidate.text, candidate.ocrConfidence);
            if (score > 0) {
              return candidate.copyWith(
                entityType: EntityType.name,
                classificationConfidence: (score + 0.08).clamp(0.0, 0.98),
              );
            }
          }

          if (candidate.isName) {
            return candidate.copyWith(
              classificationConfidence:
                  (candidate.classificationConfidence + 0.08).clamp(0.0, 0.98),
            );
          }

          return candidate;
        })
        .toList(growable: false);
  }

  double _medianHeight(List<ContactCandidate> items) {
    if (items.isEmpty) return 24;
    final heights = items.map((c) => c.box.height).toList()..sort();
    return heights[heights.length ~/ 2];
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  ContactCandidate _ignorable(
    RecognizedText fragment,
    EntityType type,
    String cleaned,
    double confidence,
  ) => ContactCandidate(
    source: fragment,
    entityType: type,
    classificationConfidence: confidence,
    normalizedText: cleaned,
  );

  String _stripListMarker(String value) =>
      value.replaceFirst(_leadingSerial, '').trim();

  bool _isHeading(String lower) {
    if (lower.length > 20) return false;
    final words = lower
        .replaceAll(RegExp(r'[^a-z\s.]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty || words.length > 3) return false;
    return words.every((w) => _headingKeywords.contains(w));
  }

  bool _containsKeyword(String lower, List<String> keywords) {
    for (final keyword in keywords) {
      if (RegExp(
        '(^|\\s)${RegExp.escape(keyword)}(\\s|\$|,)',
      ).hasMatch(lower)) {
        return true;
      }
    }
    return false;
  }

  /// Collapses whitespace and normalises casing for display.
  String _tidyName(String value) {
    final collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return collapsed;
    if (collapsed != collapsed.toUpperCase()) return collapsed;
    // Title-case an ALL-CAPS name so the phonebook entry looks natural.
    return collapsed
        .split(' ')
        .map(
          (w) => w.isEmpty
              ? w
              : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}
