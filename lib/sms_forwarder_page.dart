import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:another_telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_log.dart';
import 'debug_log_page.dart';
import 'file_logger.dart';
import 'log_entry.dart';
import 'loop_detector.dart';
import 'real_sms_service.dart';
import 'settings_service.dart';
import 'sms_forwarder_service.dart';
import 'sms_service.dart';
import 'sms_utils.dart';

class SmsForwarderPage extends StatefulWidget {
  const SmsForwarderPage({
    super.key,
    this.smsService,
    this.permissionsGrantedOverride,
    this.logger,
  });

  /// Injected [SmsService] for tests. Defaults to [RealSmsService] in production.
  final SmsService? smsService;

  /// When non-null, overrides the Android permission check result.
  /// Set to `true` in widget tests to bypass [permission_handler].
  final bool? permissionsGrantedOverride;

  /// Injected [FileLogger] for production. Null in tests.
  final FileLogger? logger;

  @override
  State<SmsForwarderPage> createState() => _SmsForwarderPageState();
}

class _SmsForwarderPageState extends State<SmsForwarderPage>
    with WidgetsBindingObserver {
  static const _methodChannel = MethodChannel(
    'dev.kkweon.sms_forwarder/telephony',
  );

  late final SmsService _smsService;

  SettingsService? _settings;
  LoopDetector? _loopDetector;
  bool _permissionsGranted = false;
  bool _forwardingEnabled = false;
  bool _loopDetected = false;
  List<String> _destinationNumbers = [];
  List<String> _ownNumbers = [];
  List<LogEntry> _forwardingLogs = [];
  final _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _smsService = widget.smsService ?? RealSmsService();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadSettings();
  }

  Future<void> _init() async {
    await _checkPermissions();
    await _loadSettings();
    await _loadOwnNumbers();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _smsService.stopListening();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    if (widget.permissionsGrantedOverride != null) {
      setState(() => _permissionsGranted = widget.permissionsGrantedOverride!);
      return;
    }
    final sms = await Permission.sms.status;
    final phone = await Permission.phone.status;
    appLog('[SMS] permissions: sms=${sms.name} phone=${phone.name}');
    if (!mounted) return;
    setState(() {
      _permissionsGranted = sms.isGranted && phone.isGranted;
    });
  }

  Future<void> _requestPermissions() async {
    final statuses = await [Permission.sms, Permission.phone].request();
    final granted = statuses.values.every((s) => s.isGranted);
    if (!mounted) return;
    setState(() => _permissionsGranted = granted);
    if (granted) _startListening();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.load();
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
      _forwardingLogs = settings.forwardingLogs;
    });
    appLog(
      '[SMS] loadSettings: enabled=$_forwardingEnabled permissions=$_permissionsGranted numbers=$_destinationNumbers',
    );
    if (_permissionsGranted) _startListening();
  }

  Future<void> _loadOwnNumbers() async {
    if (widget.permissionsGrantedOverride != null) return; // skip in tests
    try {
      final numbers =
          await _methodChannel.invokeListMethod<String>('getOwnPhoneNumbers') ??
          [];
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

  void _startListening() {
    appLog('[SMS] startListening called');
    _smsService.startListening(_onMessage);
  }

  void _onMessage(SmsMessage message) async {
    appLog(
      '[SMS] FG handler fired: from=${message.address} body=${message.body}',
    );
    try {
      if (!_forwardingEnabled) {
        appLog('[SMS] FG: forwarding disabled, skipping');
        return;
      }
      final body = preprocessBody(message.body ?? '');
      if (!containsVerificationCode(body)) {
        appLog('[SMS] FG: no keyword match, skipping. body="$body"');
        return;
      }
      final loopDetected = await _loopDetector!.countForward(
        onLoopDetected: () => _settings!.setForwardingEnabled(false),
      );
      if (loopDetected) {
        if (!mounted) return;
        setState(() {
          _forwardingEnabled = false;
          _loopDetected = true;
        });
        appLog('[SMS] FG: loop detected, aborting forward');
        return;
      }
      appLog('[SMS] FG: forwarding to $_destinationNumbers');
      forwardSms(
        smsService: _smsService,
        message: message,
        destinationNumbers: _destinationNumbers,
      ).then((newEntries) async {
        final logs = [
          ...newEntries,
          ..._forwardingLogs,
        ].take(maxLogEntries).toList();
        await _settings!.saveLogs(logs);
        if (!mounted) return;
        setState(() => _forwardingLogs = logs);
        appLog('[SMS] FG: done, ${newEntries.length} entries logged');
      });
    } catch (e, stack) {
      appLog('[SMS] FG ERROR in _onMessage: $e\n$stack');
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
    setState(() => _forwardingLogs = []);
    await _settings!.clearLogs();
  }

  Future<void> _resetLoop() async {
    await _loopDetector!.reset();
    if (!mounted) return;
    setState(() => _loopDetected = false);
  }

  @override
  Widget build(BuildContext context) {
    final canToggle = _permissionsGranted && _destinationNumbers.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Forwarder'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
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
                _permissionsGranted ? Icons.check_circle : Icons.error,
                color: _permissionsGranted ? Colors.green : Colors.red,
              ),
              title: Text(
                _permissionsGranted
                    ? 'SMS permissions granted'
                    : 'SMS permissions required',
              ),
              trailing: _permissionsGranted
                  ? null
                  : ElevatedButton(
                      onPressed: _requestPermissions,
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
                      if (value) _startListening();
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
                      if (_forwardingLogs.isNotEmpty)
                        TextButton(
                          onPressed: _clearLogs,
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                  if (_forwardingLogs.isEmpty)
                    const Text(
                      'No messages forwarded yet',
                      style: TextStyle(color: Colors.grey),
                    )
                  else
                    ...List.generate(_forwardingLogs.length, (i) {
                      final entry = _forwardingLogs[i];
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
