/// A message handed to [planForSms]. Decouples the planner from the
/// `another_telephony` package so a notification listener (or any other
/// source) can feed in events with the same shape.
class IncomingMessage {
  final String? address;
  final String? body;
  final String? packageName;
  final String? notificationKey;
  final int? postTimeMs;

  const IncomingMessage({
    this.address,
    this.body,
    this.packageName,
    this.notificationKey,
    this.postTimeMs,
  });

  factory IncomingMessage.fromMap(Map<dynamic, dynamic> map) => IncomingMessage(
    address: map['sender'] as String?,
    body: map['body'] as String?,
    packageName: map['packageName'] as String?,
    notificationKey: map['key'] as String?,
    postTimeMs: (map['postTime'] as num?)?.toInt(),
  );
}
