/// Lifecycle state of a locally-registered contact (§14).
///
/// Transitions are deliberately one-way apart from [active] -> [error] ->
/// [active], so that a re-run of cleanup can never corrupt a finished record
/// (§16 idempotency).
enum TemporaryContactStatus {
  /// Present in the phonebook and not yet past its expiry.
  active,

  /// Past expiry, deletion not yet performed.
  expired,

  /// Successfully removed from the phonebook by this app.
  deleted,

  /// The OS contact was gone when we tried to delete it — the user most
  /// likely removed it themselves (§16).
  missing,

  /// Deletion attempted and failed; will be retried.
  error;

  static TemporaryContactStatus fromName(String value) =>
      TemporaryContactStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => TemporaryContactStatus.error,
      );

  /// Terminal states are never revisited by the cleanup worker.
  bool get isTerminal =>
      this == TemporaryContactStatus.deleted ||
      this == TemporaryContactStatus.missing;

  String get label => switch (this) {
        TemporaryContactStatus.active => 'Active',
        TemporaryContactStatus.expired => 'Expired',
        TemporaryContactStatus.deleted => 'Removed',
        TemporaryContactStatus.missing => 'Already gone',
        TemporaryContactStatus.error => 'Retrying',
      };
}

/// A row in the local `temporary_contacts` registry (§13, §14).
///
/// [osContactId] is the anchor for safe deletion: cleanup resolves contacts
/// **only** by this identifier, never by name (§13).
class TemporaryContact {
  const TemporaryContact({
    required this.id,
    required this.osContactId,
    required this.name,
    required this.phone,
    required this.createdAt,
    required this.expiresAt,
    required this.status,
    this.createdByApp = true,
    this.lastCheckedAt,
    this.retryCount = 0,
  });

  /// Local SQLite primary key. `null` before the first insert.
  final int? id;

  /// Stable identifier returned by the platform contacts API.
  final String osContactId;

  final String name;
  final String phone;
  final DateTime createdAt;

  /// `null` means permanent — such rows are registered only when the user
  /// later converts them, and are never auto-deleted.
  final DateTime? expiresAt;

  final TemporaryContactStatus status;

  /// Guards against deleting anything this app did not create (§13).
  final bool createdByApp;

  final DateTime? lastCheckedAt;

  /// Consecutive failed deletion attempts; bounds retry (§15).
  final int retryCount;

  bool get isPermanent => expiresAt == null;

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now);

  /// Time left before expiry; `null` when permanent, [Duration.zero] when due.
  Duration? remainingAt(DateTime now) {
    if (expiresAt == null) return null;
    final delta = expiresAt!.difference(now);
    return delta.isNegative ? Duration.zero : delta;
  }

  /// Eligible for automatic deletion.
  bool isDueForCleanup(DateTime now) =>
      createdByApp &&
      !status.isTerminal &&
      expiresAt != null &&
      !expiresAt!.isAfter(now) &&
      retryCount < 5;

  TemporaryContact copyWith({
    int? id,
    String? name,
    String? phone,
    DateTime? expiresAt,
    bool clearExpiry = false,
    TemporaryContactStatus? status,
    DateTime? lastCheckedAt,
    int? retryCount,
  }) =>
      TemporaryContact(
        id: id ?? this.id,
        osContactId: osContactId,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        createdAt: createdAt,
        expiresAt: clearExpiry ? null : (expiresAt ?? this.expiresAt),
        status: status ?? this.status,
        createdByApp: createdByApp,
        lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
        retryCount: retryCount ?? this.retryCount,
      );

  // ── Persistence mapping ───────────────────────────────────────────────────
  static const table = 'temporary_contacts';

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'os_contact_id': osContactId,
        'name': name,
        'phone': phone,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        'expires_at': expiresAt?.toUtc().millisecondsSinceEpoch,
        'status': status.name,
        'created_by_app': createdByApp ? 1 : 0,
        'last_checked_at': lastCheckedAt?.toUtc().millisecondsSinceEpoch,
        'retry_count': retryCount,
      };

  factory TemporaryContact.fromRow(Map<String, Object?> row) {
    DateTime? at(String key) {
      final v = row[key] as int?;
      return v == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).toLocal();
    }

    return TemporaryContact(
      id: row['id'] as int?,
      osContactId: row['os_contact_id'] as String,
      name: (row['name'] as String?) ?? '',
      phone: (row['phone'] as String?) ?? '',
      createdAt: at('created_at') ?? DateTime.now(),
      expiresAt: at('expires_at'),
      status: TemporaryContactStatus.fromName(row['status'] as String? ?? 'error'),
      createdByApp: (row['created_by_app'] as int? ?? 1) == 1,
      lastCheckedAt: at('last_checked_at'),
      retryCount: row['retry_count'] as int? ?? 0,
    );
  }
}
