import 'package:permission_handler/permission_handler.dart' as ph;

/// The runtime permissions this app asks for, in the order they are requested.
enum AppPermission {
  /// `TelephonyManager.line1Number` needs it to learn our own number, which
  /// is what stops a forwarded message from being forwarded again.
  phone(
    label: 'Phone',
    rationale: 'Detects your own number so forwarding loops are blocked.',
  ),

  /// RECEIVE_SMS feeds `SmsReceiver`; SEND_SMS performs the forward. Without
  /// it the app can still read RCS via the notification listener, but nothing
  /// can be sent.
  sms(
    label: 'SMS',
    rationale: 'Reads incoming messages and sends the forwarded copy.',
  ),

  /// POST_NOTIFICATIONS gates the test-notification button. Android 13+ drops
  /// posts *silently* when it is denied, so the button appears to do nothing.
  notifications(
    label: 'Notifications',
    rationale: 'Required for the test-notification button to work.',
  );

  const AppPermission({required this.label, required this.rationale});

  final String label;
  final String rationale;
}

/// Outcome of a permission check or request.
///
/// [permanentlyDenied] matters for the UI: re-requesting is a no-op once
/// Android has locked the choice in, so the only way forward is app settings.
enum PermissionState {
  granted,
  denied,
  permanentlyDenied,

  /// The platform could not be reached — e.g. `request()` was called before
  /// the Android activity attached. Retryable, unlike a denial.
  unavailable;

  bool get isGranted => this == PermissionState.granted;
  bool get needsSettings => this == PermissionState.permanentlyDenied;
}

/// Testable seam over `permission_handler`.
///
/// The UI talks to this instead of the plugin so widget tests can drive every
/// permission state without a device.
abstract class AppPermissions {
  Future<PermissionState> check(AppPermission permission);

  Future<PermissionState> request(AppPermission permission);

  Future<void> openAppSettings();
}

/// Production implementation backed by `permission_handler`.
class PlatformAppPermissions implements AppPermissions {
  const PlatformAppPermissions();

  static const _plugin = <AppPermission, ph.Permission>{
    AppPermission.phone: ph.Permission.phone,
    AppPermission.sms: ph.Permission.sms,
    AppPermission.notifications: ph.Permission.notification,
  };

  @override
  Future<PermissionState> check(AppPermission permission) =>
      _guard(() async => _map(await _plugin[permission]!.status));

  @override
  Future<PermissionState> request(AppPermission permission) =>
      _guard(() async => _map(await _plugin[permission]!.request()));

  @override
  Future<void> openAppSettings() => ph.openAppSettings();

  /// A platform failure (no attached activity yet) is [PermissionState
  /// .unavailable], never a denial — the caller retries it later instead of
  /// nagging the user about a choice they never made.
  Future<PermissionState> _guard(Future<PermissionState> Function() op) async {
    try {
      return await op();
    } catch (_) {
      return PermissionState.unavailable;
    }
  }

  static PermissionState _map(ph.PermissionStatus status) {
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return PermissionState.granted;
    }
    if (status.isPermanentlyDenied) return PermissionState.permanentlyDenied;
    return PermissionState.denied;
  }
}
