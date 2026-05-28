import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../forwarding/sms_utils.dart';
import '../forwarding/telephony_bridge.dart';
import '../logging/app_log.dart';
import '../notifications/notification_bridge.dart';
import '../settings/forward_event.dart';
import '../settings/loop_detector.dart';
import '../settings/settings_service.dart';
import 'debug_log_page.dart';
import '../logging/file_logger.dart';

const _prefsMigrationSeen = 'migration_notification_listener_v1_seen';

class SmsForwarderPage extends StatefulWidget {
  const SmsForwarderPage({
    super.key,
    this.notificationAccessGrantedOverride,
    this.logger,
  });

  /// When non-null, overrides the platform notification-access check.
  /// Set to `true` in widget tests to skip the platform call.
  final bool? notificationAccessGrantedOverride;

  /// Injected [FileLogger] for production. Null in tests.
  final FileLogger? logger;

  @override
  State<SmsForwarderPage> createState() => _SmsForwarderPageState();
}

class _SmsForwarderPageState extends State<SmsForwarderPage>
    with WidgetsBindingObserver {
  SettingsService? _settings;
  LoopDetector? _loopDetector;
  bool _notificationAccessGranted = false;
  bool _forwardingEnabled = false;
  bool _loopDetected = false;
  List<String> _destinationNumbers = [];
  List<String> _ownNumbers = [];
  List<ForwardEvent> _forwardEvents = [];
  final _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNotificationAccess();
      _loadSettings(reload: true);
    }
  }

  Future<void> _init() async {
    await _checkNotificationAccess();
    await _loadSettings();
    await _loadOwnNumbers();
    await _maybeShowMigrationDialog();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _checkNotificationAccess() async {
    final bool granted;
    if (widget.notificationAccessGrantedOverride != null) {
      granted = widget.notificationAccessGrantedOverride!;
    } else {
      granted = await NotificationBridge.instance.isAccessGranted();
    }
    appLog('[NL] notification access granted=$granted');
    if (!mounted) return;
    setState(() => _notificationAccessGranted = granted);
  }

  Future<void> _maybeShowMigrationDialog() async {
    if (widget.notificationAccessGrantedOverride != null) {
      return; // skip in tests
    }
    if (_notificationAccessGranted) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefsMigrationSeen) == true) return;
    await prefs.setBool(_prefsMigrationSeen, true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notification access required'),
        content: const Text(
          'This update switches from SMS reading to notification access, '
          'which lets the app forward both SMS and RCS codes from Google '
          'Messages. Tap Open Settings to enable it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              NotificationBridge.instance.openSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSettings({bool reload = false}) async {
    final settings = await SettingsService.load();
    if (reload) await settings.reload();
    final loopDetector = await LoopDetector.load();
    final normalizedNumbers = settings.destinationNumbers
        .map((n) => normalizePhone(n) ?? n)
        .toSet()
        .toList();
    await settings.setDestinationNumbers(normalizedNumbers);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loopDetector = loopDetector;
      _forwardingEnabled = settings.forwardingEnabled;
      _loopDetected = loopDetector.detected;
      _destinationNumbers = normalizedNumbers;
      _forwardEvents = settings.forwardEvents;
    });
    appLog(
      '[SMS] loadSettings: enabled=$_forwardingEnabled access=$_notificationAccessGranted numbers=$_destinationNumbers',
    );
  }

  Future<void> _loadOwnNumbers() async {
    if (widget.notificationAccessGrantedOverride != null) {
      return; // skip in tests
    }
    try {
      // Phone permission is required by TelephonyManager.line1Number on
      // newer Android. Request once; user can deny without breaking core
      // functionality (own-number dedup just won't work).
      final phone = await Permission.phone.status;
      if (!phone.isGranted) {
        await Permission.phone.request();
      }
      final numbers = await TelephonyBridge.instance.getOwnPhoneNumbers();
      if (!mounted) return;
      setState(() {
        _ownNumbers = numbers
            .map((n) => normalizePhone(n))
            .whereType<String>()
            .toList();
      });
      appLog('[SMS] own numbers: $_ownNumbers');
    } catch (e) {
      appLog('[SMS] Could not get own phone numbers: $e');
    }
  }

  void _addNumber() {
    final normalized = normalizePhone(_phoneController.text);
    if (normalized == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid number — need at least 7 digits'),
        ),
      );
      return;
    }
    if (_ownNumbers.contains(normalized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot add your own number — this would create a forwarding loop',
          ),
        ),
      );
      return;
    }
    if (_destinationNumbers.contains(normalized)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Number already added')));
      _phoneController.clear();
      return;
    }
    final updatedNumbers = [..._destinationNumbers, normalized];
    setState(() {
      _destinationNumbers = updatedNumbers;
      _phoneController.clear();
    });
    _settings!.setDestinationNumbers(updatedNumbers);
  }

  void _removeNumber(int index) {
    final updatedNumbers = [..._destinationNumbers]..removeAt(index);
    setState(() => _destinationNumbers = updatedNumbers);
    _settings!.setDestinationNumbers(updatedNumbers);
  }

  Future<void> _clearLogs() async {
    setState(() => _forwardEvents = []);
    await _settings!.clearForwardEvents();
  }

  Future<void> _resetLoop() async {
    await _loopDetector!.reset();
    if (!mounted) return;
    setState(() => _loopDetected = false);
  }

  Future<void> _postTestNotification() async {
    try {
      await NotificationBridge.instance.postTestNotification();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Test notification posted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Test failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canToggle =
        _notificationAccessGranted && _destinationNumbers.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Forwarder'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.science_outlined),
            tooltip: 'Post test notification',
            onPressed: _postTestNotification,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh logs',
            onPressed: () => _loadSettings(reload: true),
          ),
          if (widget.logger != null)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: 'Debug log',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DebugLogPage(logger: widget.logger!),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loopDetected)
            Card(
              color: Colors.red.shade50,
              child: ListTile(
                leading: const Icon(Icons.warning_amber, color: Colors.red),
                title: const Text(
                  'Forwarding loop detected',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  'Forwarding was automatically disabled to prevent a loop.',
                ),
                trailing: TextButton(
                  onPressed: _resetLoop,
                  child: const Text('Reset'),
                ),
              ),
            ),
          Card(
            child: ListTile(
              leading: Icon(
                _notificationAccessGranted ? Icons.check_circle : Icons.error,
                color: _notificationAccessGranted ? Colors.green : Colors.red,
              ),
              title: Text(
                _notificationAccessGranted
                    ? 'Notification access granted'
                    : 'Notification access required',
              ),
              subtitle: const Text(
                'Reads Google Messages notifications to forward both SMS and RCS verification codes.',
              ),
              trailing: _notificationAccessGranted
                  ? null
                  : ElevatedButton(
                      onPressed: () =>
                          NotificationBridge.instance.openSettings(),
                      child: const Text('Grant'),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              title: const Text('Forwarding Enabled'),
              subtitle: Text(_forwardingEnabled ? 'Active' : 'Inactive'),
              value: _forwardingEnabled,
              onChanged: canToggle
                  ? (value) {
                      setState(() => _forwardingEnabled = value);
                      _settings!.setForwardingEnabled(value);
                    }
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Detection Keywords',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: keywords
                        .map((k) => Chip(label: Text(k)))
                        .toList(),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Matches if a keyword + 4–8 digit number are both present (case-insensitive)',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Destination Numbers',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            hintText: '+1234567890',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _addNumber(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle),
                        onPressed: _addNumber,
                      ),
                    ],
                  ),
                  if (_destinationNumbers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'No numbers added yet',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    ...List.generate(
                      _destinationNumbers.length,
                      (i) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_destinationNumbers[i]),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _removeNumber(i),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Forwarding Log',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (_forwardEvents.isNotEmpty)
                        TextButton(
                          onPressed: _clearLogs,
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                  if (_forwardEvents.isEmpty)
                    const Text(
                      'No messages forwarded yet',
                      style: TextStyle(color: Colors.grey),
                    )
                  else
                    ...List.generate(_forwardEvents.length, (i) {
                      final entry = _forwardEvents[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          entry.failed
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          color: entry.failed ? Colors.red : Colors.green,
                          size: 20,
                        ),
                        title: Text('From: ${entry.from}  →  ${entry.to}'),
                        subtitle: Text(
                          entry.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          formatTime(entry.time),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
