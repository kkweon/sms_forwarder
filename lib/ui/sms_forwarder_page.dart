import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../forwarding/sms_utils.dart';
import '../forwarding/telephony_bridge.dart';
import '../logging/app_log.dart';
import '../notifications/notification_bridge.dart';
import '../permissions/app_permissions.dart';
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
    this.permissions = const PlatformAppPermissions(),
  });

  /// When non-null, overrides the platform notification-access check.
  /// Set to `true` in widget tests to skip the platform call.
  final bool? notificationAccessGrantedOverride;

  /// Injected [FileLogger] for production. Null in tests.
  final FileLogger? logger;

  /// Runtime-permission seam; widget tests inject a fake.
  final AppPermissions permissions;

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
  Map<AppPermission, PermissionState> _permissionStates = const {};
  final _phoneController = TextEditingController();

  AppPermissions get _permissions => widget.permissions;

  /// True only when nothing stands between an incoming code and a forward.
  bool get _setupComplete =>
      _notificationAccessGranted && _missingPermissions.isEmpty;

  /// Permissions the user still has to act on, in declaration order.
  ///
  /// Unknown (not checked yet) and [PermissionState.unavailable] are both
  /// excluded: neither is the user's doing, and both resolve on their own, so
  /// neither should flash a banner asking them to fix something.
  List<AppPermission> get _missingPermissions =>
      AppPermission.values.where((p) {
        final state = _permissionStates[p];
        return state != null &&
            !state.isGranted &&
            state != PermissionState.unavailable;
      }).toList();

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
      // Catches permissions granted in system settings while we were
      // backgrounded, and retries any request that had no activity to run on.
      _refreshPermissions();
    }
  }

  Future<void> _init() async {
    await _checkNotificationAccess();
    await _loadSettings();
    await _ensurePermissions();
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

  /// Prompts for every not-yet-granted permission, one at a time.
  ///
  /// Each permission is handled independently: on a cold start a request can
  /// come back [PermissionState.unavailable] because the Android activity has
  /// not attached yet, and one shared failure must not swallow the requests
  /// that follow it. Anything unavailable is retried on the next resume,
  /// while an outright denial is left alone — the user answered, and the
  /// banner in the UI is how they change their mind.
  Future<void> _ensurePermissions() async {
    final states = <AppPermission, PermissionState>{};
    for (final permission in AppPermission.values) {
      var state = await _permissions.check(permission);
      if (state == PermissionState.denied) {
        state = await _permissions.request(permission);
        appLog('[PERM] ${permission.name} -> ${state.name}');
      }
      states[permission] = state;
    }
    if (!mounted) return;
    setState(() => _permissionStates = states);
  }

  /// Re-reads permission states without prompting, and retries anything that
  /// was [PermissionState.unavailable] now that an activity is attached.
  Future<void> _refreshPermissions() async {
    final states = <AppPermission, PermissionState>{};
    var retryable = false;
    for (final permission in AppPermission.values) {
      final state = await _permissions.check(permission);
      states[permission] = state;
      if (state == PermissionState.unavailable) retryable = true;
    }
    if (!mounted) return;
    setState(() => _permissionStates = states);
    if (retryable) await _ensurePermissions();
  }

  /// Grant button on the banner: prompt, or send the user to app settings
  /// when Android has locked the choice in and a prompt would do nothing.
  Future<void> _grantPermission(AppPermission permission) async {
    if (_permissionStates[permission]?.needsSettings ?? false) {
      await _permissions.openAppSettings();
      return;
    }
    final state = await _permissions.request(permission);
    appLog('[PERM] ${permission.name} (user tap) -> ${state.name}');
    if (!mounted) return;
    setState(
      () => _permissionStates = {..._permissionStates, permission: state},
    );
  }

  Future<void> _loadOwnNumbers() async {
    if (widget.notificationAccessGrantedOverride != null) {
      return; // skip in tests
    }
    try {
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
    // Ask before posting: a denied POST_NOTIFICATIONS makes the platform drop
    // the notification without raising anything, which looks like a dead
    // button. Prompting here (rather than only at startup) is what makes the
    // button self-healing if the permission was denied earlier.
    var state = await _permissions.check(AppPermission.notifications);
    if (state == PermissionState.denied) {
      state = await _permissions.request(AppPermission.notifications);
    }
    if (mounted) {
      setState(
        () => _permissionStates = {
          ..._permissionStates,
          AppPermission.notifications: state,
        },
      );
    }
    if (state.needsSettings) {
      if (!mounted) return;
      _showBlockedSnackBar('Notifications are turned off for SMS Forwarder.');
      return;
    }
    try {
      await NotificationBridge.instance.postTestNotification();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Test notification posted')));
    } on PlatformException catch (e) {
      appLog('[NL] test notification blocked: ${e.code} ${e.message}');
      if (!mounted) return;
      if (e.code == NotificationBridge.blockedErrorCode) {
        _showBlockedSnackBar(e.message ?? 'Notifications are turned off.');
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Test failed: ${e.message}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Test failed: $e')));
    }
  }

  void _showBlockedSnackBar(String reason) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$reason The test cannot run until it is enabled.'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: NotificationBridge.instance.openNotificationSettings,
        ),
      ),
    );
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
          // One status card for the whole setup. It goes green only when
          // notification access AND every runtime permission is in place —
          // a green check while SMS permission is denied would be a lie.
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    _setupComplete ? Icons.check_circle : Icons.error,
                    color: _setupComplete ? Colors.green : Colors.red,
                  ),
                  title: Text(
                    _setupComplete ? 'Ready to forward' : 'Setup incomplete',
                  ),
                  subtitle: Text(
                    _setupComplete
                        ? 'Notification access and all permissions granted.'
                        : 'Forwarding will not work until the items below are '
                              'granted.',
                  ),
                ),
                if (!_notificationAccessGranted)
                  _SetupItem(
                    label: 'Notification access',
                    rationale:
                        'Reads Google Messages notifications to forward both '
                        'SMS and RCS verification codes.',
                    buttonLabel: 'Grant',
                    onPressed: NotificationBridge.instance.openSettings,
                  ),
                for (final permission in _missingPermissions)
                  _SetupItem(
                    label: permission.label,
                    rationale: permission.rationale,
                    // A prompt is a no-op once Android locks the choice in,
                    // so send the user where the choice can still be changed.
                    buttonLabel: _permissionStates[permission]!.needsSettings
                        ? 'Settings'
                        : 'Grant',
                    onPressed: () => _grantPermission(permission),
                  ),
              ],
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
                    'Matches if one of these phrases appears together with a '
                    '4–8 character code containing a digit (case-insensitive). '
                    'A bare "code" or "PIN" only counts next to the code '
                    'itself, so "zip code" style messages are not forwarded.',
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

/// One outstanding setup item inside the status card: what is missing, why it
/// is needed, and the button that fixes it.
class _SetupItem extends StatelessWidget {
  const _SetupItem({
    required this.label,
    required this.rationale,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String label;
  final String rationale;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.remove_circle_outline, color: Colors.red),
      title: Text(label),
      subtitle: Text(rationale),
      trailing: ElevatedButton(onPressed: onPressed, child: Text(buttonLabel)),
    );
  }
}
