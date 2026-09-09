/// Expiry presets offered on the review screen (§11).
enum ExpiryOption {
  oneHour(Duration(hours: 1), '1 Hour'),
  sixHours(Duration(hours: 6), '6 Hours'),
  twelveHours(Duration(hours: 12), '12 Hours'),
  oneDay(Duration(hours: 24), '24 Hours'),
  threeDays(Duration(days: 3), '3 Days'),
  sevenDays(Duration(days: 7), '7 Days'),
  custom(null, 'Custom Date & Time'),
  never(null, 'Never');

  const ExpiryOption(this.duration, this.label);

  /// `null` for [custom] (user supplies an absolute instant) and for [never].
  final Duration? duration;
  final String label;

  /// [never] means the contact is permanent (§11).
  bool get isPermanent => this == ExpiryOption.never;
  bool get requiresPicker => this == ExpiryOption.custom;

  /// Resolves to an absolute expiry instant.
  ///
  /// Returns `null` for permanent contacts. [customValue] is required for
  /// [custom] and must already have been validated as being in the future.
  DateTime? resolve(DateTime now, {DateTime? customValue}) {
    if (isPermanent) return null;
    if (this == ExpiryOption.custom) return customValue;
    return now.add(duration!);
  }
}

/// The user's expiry choice for one contact, in a form that survives editing.
class ExpirySelection {
  const ExpirySelection({required this.option, this.customValue});

  const ExpirySelection.permanent()
      : option = ExpiryOption.never,
        customValue = null;

  final ExpiryOption option;
  final DateTime? customValue;

  bool get isTemporary => !option.isPermanent;

  /// True when the selection cannot produce a valid future instant.
  bool isInvalidAt(DateTime now) =>
      option.requiresPicker &&
      (customValue == null || !customValue!.isAfter(now));

  DateTime? resolve(DateTime now) =>
      option.resolve(now, customValue: customValue);

  String get label => option == ExpiryOption.custom && customValue != null
      ? 'Custom'
      : option.label;
}
