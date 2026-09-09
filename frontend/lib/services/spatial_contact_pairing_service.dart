import 'dart:math' as math;

import '../models/contact_candidate.dart';
import '../models/extracted_contact.dart';

/// One scored (name, phone) hypothesis. Exposed for testing and for the
/// "why was this paired?" debug overlay.
class PairingScore {
  const PairingScore({
    required this.name,
    required this.phone,
    required this.verticalAlignmentScore,
    required this.rowOverlapScore,
    required this.horizontalDistanceScore,
    required this.nameConfidence,
    required this.phoneConfidence,
    required this.readingOrderScore,
    required this.total,
  });

  final ContactCandidate name;
  final ContactCandidate phone;

  final double verticalAlignmentScore;
  final double rowOverlapScore;
  final double horizontalDistanceScore;
  final double nameConfidence;
  final double phoneConfidence;
  final double readingOrderScore;

  /// Weighted sum in [0, 1].
  final double total;
}

/// Geometry derived from the page itself, so no threshold is hardcoded to a
/// particular resolution (§9 "do not use one hardcoded threshold").
class RowMetrics {
  const RowMetrics({
    required this.medianTextHeight,
    required this.estimatedRowSpacing,
    required this.rowThreshold,
    required this.documentWidth,
    required this.documentHeight,
  });

  final double medianTextHeight;
  final double estimatedRowSpacing;

  /// Maximum vertical centre distance still considered "the same row".
  final double rowThreshold;

  final double documentWidth;
  final double documentHeight;
}

/// Associates names with phone numbers using bounding-box geometry (§9).
///
/// The algorithm is:
///   1. derive a resolution-independent row threshold from the page,
///   2. score every (name, phone) pair that plausibly shares a row,
///   3. resolve to a 1:1 assignment greedily by descending score,
///   4. report everything that failed to pair, rather than dropping it.
class SpatialContactPairingService {
  const SpatialContactPairingService();

  // Relative weights. They sum to 1.0 so [PairingScore.total] stays in [0, 1].
  static const double _wVertical = 0.30;
  static const double _wOverlap = 0.25;
  static const double _wHorizontal = 0.15;
  static const double _wNameConf = 0.12;
  static const double _wPhoneConf = 0.12;
  static const double _wReadingOrder = 0.06;

  /// Minimum score for a pair to be accepted at all.
  static const double minimumAcceptedScore = 0.42;

  /// If the best and second-best scores are closer than this, the pairing is
  /// flagged ambiguous and shown to the user for confirmation.
  static const double ambiguityMargin = 0.08;

  /// Pairs [candidates] into contacts.
  ///
  /// [documentWidth]/[documentHeight] are the dimensions of the flattened
  /// document, used to scale distance penalties.
  PairingOutcome pair(
    List<ContactCandidate> candidates, {
    required double documentWidth,
    required double documentHeight,
  }) {
    final names = candidates.where((c) => c.isName).toList();
    final phones = candidates.where((c) => c.isPhone).toList();

    final metrics = computeRowMetrics(
      candidates,
      documentWidth: documentWidth,
      documentHeight: documentHeight,
    );

    if (names.isEmpty || phones.isEmpty) {
      return PairingOutcome(
        contacts: const [],
        unmatchedNames: names,
        unmatchedPhones: phones,
        metrics: metrics,
      );
    }

    // 1. Score every plausible hypothesis.
    final hypotheses = <PairingScore>[];
    for (final phone in phones) {
      for (final name in names) {
        final score = scorePair(name, phone, metrics);
        if (score.total >= minimumAcceptedScore) hypotheses.add(score);
      }
    }

    // 2. Greedy 1:1 assignment, best-first.
    hypotheses.sort((a, b) => b.total.compareTo(a.total));

    final usedNames = <ContactCandidate>{};
    final usedPhones = <ContactCandidate>{};
    final accepted = <PairingScore>[];

    for (final h in hypotheses) {
      if (usedNames.contains(h.name) || usedPhones.contains(h.phone)) continue;
      accepted.add(h);
      usedNames.add(h.name);
      usedPhones.add(h.phone);
    }

    // 3. Flag pairings whose runner-up was nearly as good.
    final contacts = <ExtractedContact>[];
    for (var i = 0; i < accepted.length; i++) {
      final winner = accepted[i];
      final runnerUp = hypotheses
          .where((h) =>
              h.phone == winner.phone &&
              h.name != winner.name &&
              !usedNames.contains(h.name))
          .fold<double?>(null, (best, h) => best == null || h.total > best ? h.total : best);

      final issues = <PairingIssue>{};
      if (runnerUp != null && (winner.total - runnerUp).abs() < ambiguityMargin) {
        issues.add(PairingIssue.ambiguousPairing);
      }
      if (winner.name.ocrConfidence < 0.6 || winner.phone.ocrConfidence < 0.6) {
        issues.add(PairingIssue.lowConfidence);
      }
      final parsed = winner.phone.phone;
      if (parsed == null || !parsed.isValid) {
        issues.add(PairingIssue.invalidPhone);
      }

      contacts.add(
        ExtractedContact(
          id: 'c${i}_${winner.phone.box.centerY.round()}',
          name: winner.name.text,
          phone: parsed?.isValid == true
              ? parsed!.normalizedValue
              : winner.phone.text,
          confidence: winner.total,
          parsedPhone: parsed,
          nameCandidate: winner.name,
          phoneCandidate: winner.phone,
          issues: issues,
        ),
      );
    }

    // 4. Preserve reading order: top of page first.
    contacts.sort((a, b) => (a.phoneCandidate?.box.centerY ?? 0)
        .compareTo(b.phoneCandidate?.box.centerY ?? 0));

    return PairingOutcome(
      contacts: contacts,
      unmatchedNames:
          names.where((n) => !usedNames.contains(n)).toList(growable: false),
      unmatchedPhones:
          phones.where((p) => !usedPhones.contains(p)).toList(growable: false),
      metrics: metrics,
    );
  }

  /// Derives row geometry from the detected boxes themselves.
  ///
  /// [rowThreshold] blends two independent signals — text height and observed
  /// line spacing — then clamps the result to a sane fraction of the page so a
  /// pathological detection cannot produce a threshold that merges the whole
  /// sheet into one row.
  RowMetrics computeRowMetrics(
    List<ContactCandidate> candidates, {
    required double documentWidth,
    required double documentHeight,
  }) {
    if (candidates.isEmpty) {
      final fallback = math.max(documentHeight * 0.02, 12.0);
      return RowMetrics(
        medianTextHeight: fallback,
        estimatedRowSpacing: fallback * 1.6,
        rowThreshold: fallback,
        documentWidth: documentWidth,
        documentHeight: documentHeight,
      );
    }

    final heights = candidates.map((c) => c.box.height).toList()..sort();
    final medianHeight = heights[heights.length ~/ 2];

    // Estimate line spacing from consecutive vertical centres, ignoring
    // fragments that sit on the same row.
    final centers = candidates.map((c) => c.box.centerY).toList()..sort();
    final gaps = <double>[];
    for (var i = 1; i < centers.length; i++) {
      final gap = centers[i] - centers[i - 1];
      if (gap > medianHeight * 0.5) gaps.add(gap);
    }
    gaps.sort();
    final rowSpacing =
        gaps.isEmpty ? medianHeight * 1.6 : gaps[gaps.length ~/ 2];

    // Same-row tolerance: generous enough for a baseline wobble, tight enough
    // to keep adjacent rows apart.
    var threshold = math.max(medianHeight * 0.60, rowSpacing * 0.45);

    // Never let the tolerance approach a full line, or rows merge.
    threshold = math.min(threshold, rowSpacing * 0.85);

    // Absolute guard rails relative to the page.
    threshold = threshold.clamp(
      math.max(documentHeight * 0.004, 4.0),
      math.max(documentHeight * 0.060, 12.0),
    );

    return RowMetrics(
      medianTextHeight: medianHeight,
      estimatedRowSpacing: rowSpacing,
      rowThreshold: threshold,
      documentWidth: documentWidth,
      documentHeight: documentHeight,
    );
  }

  /// Scores a single (name, phone) hypothesis.
  PairingScore scorePair(
    ContactCandidate name,
    ContactCandidate phone,
    RowMetrics metrics,
  ) {
    final dy = (name.box.centerY - phone.box.centerY).abs();

    // Vertical alignment falls off linearly out to twice the row threshold, so
    // a near-miss still scores something rather than snapping to zero.
    final vertical =
        (1.0 - (dy / (metrics.rowThreshold * 2))).clamp(0.0, 1.0).toDouble();

    final overlap = name.box.verticalOverlapRatio(phone.box);

    // Horizontal proximity, scaled by page width.
    final gap = name.box.horizontalGapTo(phone.box);
    final horizontal =
        (1.0 - (gap / math.max(metrics.documentWidth * 0.75, 1.0)))
            .clamp(0.0, 1.0)
            .toDouble();

    // On a contact sheet the name is written to the left of the number.
    final readingOrder = name.box.left <= phone.box.left ? 1.0 : 0.35;

    final total = _wVertical * vertical +
        _wOverlap * overlap +
        _wHorizontal * horizontal +
        _wNameConf * name.overallConfidence +
        _wPhoneConf * phone.overallConfidence +
        _wReadingOrder * readingOrder;

    return PairingScore(
      name: name,
      phone: phone,
      verticalAlignmentScore: vertical,
      rowOverlapScore: overlap,
      horizontalDistanceScore: horizontal,
      nameConfidence: name.overallConfidence,
      phoneConfidence: phone.overallConfidence,
      readingOrderScore: readingOrder,
      total: total.clamp(0.0, 1.0),
    );
  }
}

/// Everything the pairing stage produced, including its leftovers (§9).
class PairingOutcome {
  const PairingOutcome({
    required this.contacts,
    required this.unmatchedNames,
    required this.unmatchedPhones,
    required this.metrics,
  });

  final List<ExtractedContact> contacts;
  final List<ContactCandidate> unmatchedNames;
  final List<ContactCandidate> unmatchedPhones;
  final RowMetrics metrics;

  bool get hasLeftovers =>
      unmatchedNames.isNotEmpty || unmatchedPhones.isNotEmpty;
}
