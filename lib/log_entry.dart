class LogEntry {
  final String time;
  final String from;
  final String to;
  final String body;
  final String status; // 'sent', 'failed', or 'timeout'

  const LogEntry({
    required this.time,
    required this.from,
    required this.to,
    required this.body,
    required this.status,
  });

  bool get failed => status != 'sent';

  Map<String, dynamic> toJson() => {
    'time': time,
    'from': from,
    'to': to,
    'body': body,
    'status': status,
  };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
    time: json['time'] as String,
    from: json['from'] as String,
    to: json['to'] as String,
    body: json['body'] as String,
    status: json['status'] as String,
  );
}
