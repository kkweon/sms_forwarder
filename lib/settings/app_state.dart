/// Snapshot of persisted state read once at the top of the background
/// handler and handed to the pure planner. Keeps the planner free of I/O.
class AppState {
  final bool forwardingEnabled;
  final List<String> destinationNumbers;
  final List<int> recentForwardTimestampsMs;

  const AppState({
    required this.forwardingEnabled,
    required this.destinationNumbers,
    required this.recentForwardTimestampsMs,
  });
}
