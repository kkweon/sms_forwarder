import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:another_telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keywords = [
  'verif', 'code', 'otp', 'passcode', 'pin', 'auth', 'confirm',
];

bool containsVerificationCode(String text) {
  if (text.isEmpty) return false;
  final hasKeyword = RegExp(
    _keywords.join('|'),
    caseSensitive: false,
  ).hasMatch(text);
  final hasDigits = RegExp(r'\b\d{4,8}\b').hasMatch(text);
  return hasKeyword && hasDigits;
}

@pragma('vm:entry-point')
Future<void> backgroundMessageHandler(SmsMessage message) async {
  debugPrint('[SMS] BG handler fired: from=${message.address} body=${message.body}');
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool('forwarding_enabled') ?? false)) {
    debugPrint('[SMS] BG: forwarding disabled, skipping');
    return;
  }
  final body = message.body ?? '';
  if (!containsVerificationCode(body)) {
    debugPrint('[SMS] BG: no keyword match, skipping');
    return;
  }
  final numbers = prefs.getStringList('destination_numbers') ?? [];
  if (numbers.isEmpty) {
    debugPrint('[SMS] BG: no destination numbers, skipping');
    return;
  }
  debugPrint('[SMS] BG: forwarding to $numbers');
  final telephony = Telephony.backgroundInstance;
  final forwardText = 'Fwd from ${message.address ?? "unknown"}:\n$body';
  final now = DateTime.now().toIso8601String();
  final from = message.address ?? 'unknown';
  final pendingEntries = <String, String>{};
  final completers = <String, Completer<void>>{};

  for (final number in numbers) {
    final completer = Completer<void>();
    completers[number] = completer;
    await telephony.sendSms(
      to: number,
      message: forwardText,
      isMultipart: true,
      statusListener: (SendStatus status) {
        debugPrint('[SMS] BG: send to $number status=$status');
        pendingEntries[number] = jsonEncode({
          'time': now,
          'from': from,
          'to': number,
          'body': body,
          'status': status == SendStatus.SENT ? 'sent' : 'failed',
        });
        if (!completer.isCompleted) completer.complete();
      },
    );
  }

  await Future.wait(completers.entries.map((e) => e.value.future.timeout(
    const Duration(seconds: 30),
    onTimeout: () {
      debugPrint('[SMS] BG: timeout waiting for status from ${e.key}');
      pendingEntries[e.key] = jsonEncode({
        'time': now,
        'from': from,
        'to': e.key,
        'body': body,
        'status': 'timeout',
      });
    },
  )));
  final log = prefs.getStringList('forwarding_log') ?? [];
  for (final entry in pendingEntries.values) {
    log.insert(0, entry);
  }
  if (log.length > 50) log.removeRange(50, log.length);
  await prefs.setStringList('forwarding_log', log);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SMS Forwarder',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const SmsForwarderPage(),
    );
  }
}

class SmsForwarderPage extends StatefulWidget {
  const SmsForwarderPage({super.key});

  @override
  State<SmsForwarderPage> createState() => _SmsForwarderPageState();
}

class _SmsForwarderPageState extends State<SmsForwarderPage> with WidgetsBindingObserver {
  final _telephony = Telephony.instance;
  bool _permissionsGranted = false;
  bool _forwardingEnabled = false;
  List<String> _destinationNumbers = [];
  List<Map<String, dynamic>> _forwardingLog = [];
  final _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    final sms = await Permission.sms.status;
    final phone = await Permission.phone.status;
    debugPrint('[SMS] permissions: sms=${sms.name} phone=${phone.name}');
    setState(() {
      _permissionsGranted = sms.isGranted && phone.isGranted;
    });
  }

  Future<void> _requestPermissions() async {
    final statuses = await [Permission.sms, Permission.phone].request();
    final granted = statuses.values.every((s) => s.isGranted);
    setState(() => _permissionsGranted = granted);
    if (granted) _startListening();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final logJson = prefs.getStringList('forwarding_log') ?? [];
    setState(() {
      _forwardingEnabled = prefs.getBool('forwarding_enabled') ?? false;
      _destinationNumbers = (prefs.getStringList('destination_numbers') ?? [])
          .map((n) => _normalizePhone(n) ?? n)
          .toSet()
          .toList();
      _forwardingLog = logJson
          .map((e) => jsonDecode(e) as Map<String, dynamic>)
          .toList();
    });
    await prefs.setStringList('destination_numbers', _destinationNumbers);
    debugPrint('[SMS] loadSettings: enabled=$_forwardingEnabled permissions=$_permissionsGranted numbers=$_destinationNumbers');
    if (_permissionsGranted) _startListening();
  }

  void _startListening() {
    debugPrint('[SMS] startListening called');
    _telephony.listenIncomingSms(
      onNewMessage: _onMessage,
      onBackgroundMessage: backgroundMessageHandler,
      listenInBackground: true,
    );
  }

  void _onMessage(SmsMessage message) {
    debugPrint('[SMS] FG handler fired: from=${message.address} body=${message.body}');
    if (!_forwardingEnabled) {
      debugPrint('[SMS] FG: forwarding disabled, skipping');
      return;
    }
    final body = message.body ?? '';
    if (!containsVerificationCode(body)) {
      debugPrint('[SMS] FG: no keyword match, skipping');
      return;
    }
    debugPrint('[SMS] FG: forwarding to $_destinationNumbers');
    final forwardText = 'Fwd from ${message.address ?? "unknown"}:\n$body';
    final now = DateTime.now().toIso8601String();
    final from = message.address ?? 'unknown';
    final pendingEntries = <String, Map<String, String>>{};
    final completers = <String, Completer<void>>{};

    for (final number in _destinationNumbers) {
      final completer = Completer<void>();
      completers[number] = completer;
      _telephony.sendSms(
        to: number,
        message: forwardText,
        isMultipart: true,
        statusListener: (SendStatus status) {
          debugPrint('[SMS] FG: send to $number status=$status');
          pendingEntries[number] = {
            'time': now,
            'from': from,
            'to': number,
            'body': body,
            'status': status == SendStatus.SENT ? 'sent' : 'failed',
          };
          if (!completer.isCompleted) completer.complete();
        },
      );
    }

    Future.wait(completers.entries.map((e) => e.value.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        debugPrint('[SMS] FG: timeout waiting for status from ${e.key}');
        pendingEntries[e.key] = {
          'time': now,
          'from': from,
          'to': e.key,
          'body': body,
          'status': 'timeout',
        };
      },
    ))).then((_) {
      setState(() {
        for (final entry in pendingEntries.values) {
          _forwardingLog.insert(0, entry);
        }
        if (_forwardingLog.length > 50) {
          _forwardingLog.removeRange(50, _forwardingLog.length);
        }
      });
      _saveLog();
    });
  }

  Future<void> _saveForwardingEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('forwarding_enabled', value);
  }

  Future<void> _saveDestinationNumbers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('destination_numbers', _destinationNumbers);
  }

  Future<void> _saveLog() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'forwarding_log',
      _forwardingLog.map((e) => jsonEncode(e)).toList(),
    );
  }

  String? _normalizePhone(String input) {
    final leadingPlus = input.trimLeft().startsWith('+');
    final digits = input.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length < 7) return null;
    return leadingPlus ? '+$digits' : digits;
  }

  void _addNumber() {
    final normalized = _normalizePhone(_phoneController.text);
    if (normalized == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid number — need at least 7 digits')),
      );
      return;
    }
    if (_destinationNumbers.contains(normalized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Number already added')),
      );
      _phoneController.clear();
      return;
    }
    setState(() {
      _destinationNumbers.add(normalized);
      _phoneController.clear();
    });
    _saveDestinationNumbers();
  }

  void _removeNumber(int index) {
    setState(() => _destinationNumbers.removeAt(index));
    _saveDestinationNumbers();
  }

  Future<void> _clearLog() async {
    setState(() => _forwardingLog.clear());
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('forwarding_log');
  }

  String _formatTime(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final canToggle = _permissionsGranted && _destinationNumbers.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Forwarder'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                _permissionsGranted ? Icons.check_circle : Icons.error,
                color: _permissionsGranted ? Colors.green : Colors.red,
              ),
              title: Text(_permissionsGranted
                  ? 'SMS permissions granted'
                  : 'SMS permissions required'),
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
                      _saveForwardingEnabled(value);
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
                  Text('Detection Keywords',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _keywords
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
                  Text('Destination Numbers',
                      style: Theme.of(context).textTheme.titleMedium),
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
                      child: Text('No numbers added yet',
                          style: TextStyle(color: Colors.grey)),
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
                      Text('Forwarding Log',
                          style: Theme.of(context).textTheme.titleMedium),
                      if (_forwardingLog.isNotEmpty)
                        TextButton(
                          onPressed: _clearLog,
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                  if (_forwardingLog.isEmpty)
                    const Text('No messages forwarded yet',
                        style: TextStyle(color: Colors.grey))
                  else
                    ...List.generate(
                      _forwardingLog.length,
                      (i) {
                        final entry = _forwardingLog[i];
                        final failed = entry['status'] != 'sent';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            failed ? Icons.error_outline : Icons.check_circle_outline,
                            color: failed ? Colors.red : Colors.green,
                            size: 20,
                          ),
                          title: Text('From: ${entry['from']}  →  ${entry['to'] ?? '?'}'),
                          subtitle: Text(
                            entry['body'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            _formatTime(entry['time'] as String),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
