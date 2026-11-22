/// The state of the sender: for the settings page and the indicator.
final class TelemetryStatus {
  /// Creates a status.
  const TelemetryStatus({
    required this.queued,
    required this.sending,
    required this.lastSentAt,
    required this.lastCheckAt,
    required this.reachable,
  });

  /// Restores a status from [toJson].
  factory TelemetryStatus.fromJson(Object? json) {
    if (json case {
      'queued': final int queued,
      'sending': final bool sending,
      'lastSentAt': final String? lastSentAt,
      'lastCheckAt': final String? lastCheckAt,
      'reachable': final bool reachable,
    }) {
      return TelemetryStatus(
        queued: queued,
        sending: sending,
        lastSentAt: lastSentAt == null ? null : DateTime.parse(lastSentAt).toUtc(),
        lastCheckAt: lastCheckAt == null ? null : DateTime.parse(lastCheckAt).toUtc(),
        reachable: reachable,
      );
    }
    throw FormatException('Invalid sender status: $json');
  }

  /// The state before the first pass.
  static const TelemetryStatus initial = TelemetryStatus(
    queued: 0,
    sending: false,
    lastSentAt: null,
    lastCheckAt: null,
    reachable: false,
  );

  /// Entries in the queue at the time of the last pass.
  final int queued;

  /// Whether a pass is running.
  final bool sending;

  /// When an entry was last accepted.
  final DateTime? lastSentAt;

  /// When the connection to the service was last checked.
  final DateTime? lastCheckAt;

  /// The result of the last connection check.
  final bool reachable;

  /// The status as JSON.
  Map<String, Object?> toJson() => {
    'queued': queued,
    'sending': sending,
    'lastSentAt': lastSentAt?.toUtc().toIso8601String(),
    'lastCheckAt': lastCheckAt?.toUtc().toIso8601String(),
    'reachable': reachable,
  };
}
