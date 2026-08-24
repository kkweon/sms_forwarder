import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_forwarder/permissions/app_permissions.dart';
import 'package:sms_forwarder/ui/sms_forwarder_page.dart';

/// Scriptable [AppPermissions] so every permission state can be exercised
/// without a device — including the states that only show up on a cold start.
class FakeAppPermissions implements AppPermissions {
  FakeAppPermissions(this._states, {this.onRequest = const {}});

  Map<AppPermission, PermissionState> _states;

  /// What `request()` resolves to, per permission. Defaults to the current
  /// state, i.e. the user dismissing the dialog without changing anything.
  Map<AppPermission, PermissionState> onRequest;

  final List<AppPermission> checked = [];
  final List<AppPermission> requested = [];
  int openAppSettingsCount = 0;

  void set(AppPermission permission, PermissionState state) =>
      _states = {..._states, permission: state};

  @override
  Future<PermissionState> check(AppPermission permission) async {
    checked.add(permission);
    return _states[permission] ?? PermissionState.granted;
  }

  @override
  Future<PermissionState> request(AppPermission permission) async {
    requested.add(permission);
    final result = onRequest[permission] ?? _states[permission]!;
    set(permission, result);
    return result;
  }

  @override
  Future<void> openAppSettings() async => openAppSettingsCount++;
}

Future<void> _pumpPage(
  WidgetTester tester,
  FakeAppPermissions permissions, {
  bool notificationAccess = true,
}) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      home: SmsForwarderPage(
        notificationAccessGrantedOverride: notificationAccess,
        permissions: permissions,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<AppPermission, PermissionState> _all(PermissionState state) => {
  for (final permission in AppPermission.values) permission: state,
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('setup status card', () {
    testWidgets('reports ready when access and all permissions are granted', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        FakeAppPermissions(_all(PermissionState.granted)),
      );

      expect(find.text('Ready to forward'), findsOneWidget);
      expect(find.text('Setup incomplete'), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Grant'), findsNothing);
    });

    testWidgets('does NOT report ready when a permission is denied', (
      tester,
    ) async {
      // The original flaw: the card showed a green check based on notification
      // access alone, while a denied SMS permission silently broke forwarding.
      final permissions = FakeAppPermissions(
        {
          ..._all(PermissionState.granted),
          AppPermission.sms: PermissionState.denied,
        },
        onRequest: {AppPermission.sms: PermissionState.denied},
      );

      await _pumpPage(tester, permissions);

      expect(find.text('Ready to forward'), findsNothing);
      expect(find.text('Setup incomplete'), findsOneWidget);
      expect(find.text('SMS'), findsOneWidget);
      expect(
        find.text('Reads incoming messages and sends the forwarded copy.'),
        findsOneWidget,
      );
    });

    testWidgets('lists every outstanding item, permissions and access alike', (
      tester,
    ) async {
      final permissions = FakeAppPermissions(
        _all(PermissionState.denied),
        onRequest: _all(PermissionState.denied),
      );

      await _pumpPage(tester, permissions, notificationAccess: false);

      expect(find.text('Notification access'), findsOneWidget);
      for (final permission in AppPermission.values) {
        expect(find.text(permission.label), findsOneWidget);
      }
    });

    testWidgets('granting from the card clears the item and turns it green', (
      tester,
    ) async {
      final permissions = FakeAppPermissions(
        {
          ..._all(PermissionState.granted),
          AppPermission.notifications: PermissionState.denied,
        },
        onRequest: {AppPermission.notifications: PermissionState.denied},
      );

      await _pumpPage(tester, permissions);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Setup incomplete'), findsOneWidget);

      // The user says yes to this prompt.
      permissions.onRequest = {
        AppPermission.notifications: PermissionState.granted,
      };
      await tester.tap(find.widgetWithText(ElevatedButton, 'Grant'));
      await tester.pumpAndSettle();

      expect(permissions.requested, contains(AppPermission.notifications));
      expect(find.text('Notifications'), findsNothing);
      expect(find.text('Ready to forward'), findsOneWidget);
    });
  });

  group('permanently denied', () {
    testWidgets('offers Settings instead of a prompt that would do nothing', (
      tester,
    ) async {
      final permissions = FakeAppPermissions({
        ..._all(PermissionState.granted),
        AppPermission.sms: PermissionState.permanentlyDenied,
      });

      await _pumpPage(tester, permissions);

      expect(find.widgetWithText(ElevatedButton, 'Settings'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Grant'), findsNothing);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Settings'));
      await tester.pumpAndSettle();

      expect(permissions.openAppSettingsCount, 1);
      // Re-prompting is a no-op once Android locks the choice in, so the UI
      // must not pretend otherwise.
      expect(permissions.requested, isEmpty);
    });

    testWidgets('is never auto-requested at startup', (tester) async {
      final permissions = FakeAppPermissions(
        _all(PermissionState.permanentlyDenied),
      );

      await _pumpPage(tester, permissions);

      expect(permissions.requested, isEmpty);
    });
  });

  group('cold-start platform failure', () {
    testWidgets('one unavailable permission does not block the others', (
      tester,
    ) async {
      // Reproduces the observed bug: `Permission.phone.request()` threw
      // "Unable to detect current Android Activity" and, because all three
      // requests shared one try block, SMS and notifications were never asked
      // for at all.
      final permissions = FakeAppPermissions(
        {
          AppPermission.phone: PermissionState.unavailable,
          AppPermission.sms: PermissionState.denied,
          AppPermission.notifications: PermissionState.denied,
        },
        onRequest: {
          AppPermission.sms: PermissionState.granted,
          AppPermission.notifications: PermissionState.granted,
        },
      );

      await _pumpPage(tester, permissions);

      expect(permissions.requested, [
        AppPermission.sms,
        AppPermission.notifications,
      ]);
    });

    testWidgets('shows no accusing banner for an unavailable permission', (
      tester,
    ) async {
      // The user denied nothing — the platform simply was not ready — so the
      // card must not ask them to fix it.
      final permissions = FakeAppPermissions(_all(PermissionState.unavailable));

      await _pumpPage(tester, permissions);

      expect(find.widgetWithText(ElevatedButton, 'Grant'), findsNothing);
      expect(find.text('Phone'), findsNothing);
    });

    testWidgets('retries an unavailable permission on resume', (tester) async {
      final permissions = FakeAppPermissions(_all(PermissionState.unavailable));

      await _pumpPage(tester, permissions);
      expect(permissions.requested, isEmpty);

      // Activity is attached by the time the app resumes.
      permissions.set(AppPermission.sms, PermissionState.denied);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(permissions.requested, contains(AppPermission.sms));
    });

    testWidgets('picks up a permission granted in system settings', (
      tester,
    ) async {
      final permissions = FakeAppPermissions({
        ..._all(PermissionState.granted),
        AppPermission.sms: PermissionState.permanentlyDenied,
      });

      await _pumpPage(tester, permissions);
      expect(find.text('Setup incomplete'), findsOneWidget);

      // User flips it on in Android settings and comes back.
      permissions.set(AppPermission.sms, PermissionState.granted);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Ready to forward'), findsOneWidget);
    });
  });
}
