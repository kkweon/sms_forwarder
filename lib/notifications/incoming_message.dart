/// A message handed to [planForSms]. Decouples the planner from the
/// `another_telephony` package so a notification listener (or any other
/// source) can feed in events with the same shape.
class IncomingMessage {
  final String? address;
  final String? body;
  final String? packageName;
  final String? notificationKey;
  final int? postTimeMs;

  /// Non-null when this event is a *diagnostic*: a notification the
  /// Kotlin listener silently dropped (package mismatch, blank body, …)
  /// surfaced to Dart for the Debug Log instead of being processed.
  /// The dispatcher logs and skips when this is set.
  final String? diag;

  const IncomingMessage({
    this.address,
    this.body,
    this.packageName,
    this.notificationKey,
    this.postTimeMs,
    this.diag,
  });

  factory IncomingMessage.fromMap(Map<dynamic, dynamic> map) => IncomingMessage(
    address: map['sender'] as String?,
    body: map['body'] as String?,
    packageName: map['packageName'] as String?,
    notificationKey: map['key'] as String?,
    postTimeMs: (map['postTime'] as num?)?.toInt(),
    diag: map['diag'] as String?,
  );
}
