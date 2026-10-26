import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../../core/utils/log.dart';
import '../domain/app_notification.dart';

/// A push the user tapped: where to go and which inbox row it was.
class PushTap {
  const PushTap({required this.route, this.notificationId});

  final String route;
  final String? notificationId;

  /// From FCM `data` ({route, notification_id, type}); null without a safe
  /// in-app route.
  static PushTap? fromData(Map<String, dynamic> data) {
    final route = safeRoute(data['route']);
    if (route == null) return null;
    return PushTap(
      route: route,
      notificationId: data['notification_id'] as String?,
    );
  }
}

/// The device side of push (NOT-01), behind an interface so tests and builds
/// without Firebase use [NoPushService].
abstract interface class PushService {
  /// Asks for permission (iOS, Android 13+, browsers) and returns this
  /// device's token, or null if refused or unavailable.
  Future<String?> enable();

  /// `ios`, `android` or `web` (`device_tokens.platform`).
  String get platform;

  /// New tokens after FCM rotates one.
  Stream<String> get tokenRefreshes;

  /// Taps on a push while the app was in the background.
  Stream<PushTap> get taps;

  /// The push that launched the app from closed, once.
  Future<PushTap?> launchTap();

  /// Drops this device's token, so a signed-out phone gets nothing more.
  Future<void> disable();
}

// FlutterFire 17 deprecates the FCM registration token in favour of the
// Firebase Installation ID (register/onRegistered). The notify Edge
// Function sends with FCM HTTP v1 `message.token`, which takes the
// registration token, so this stays on the token API until the server moves
// to FID sends (follow-up in delivery/f07-push-inbox/README.md).
// ignore_for_file: deprecated_member_use

class FcmPushService implements PushService {
  FcmPushService({required this.vapidKey});

  /// Web only.
  final String vapidKey;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  String get platform => kIsWeb
      ? 'web'
      : defaultTargetPlatform == TargetPlatform.iOS
      ? 'ios'
      : 'android';

  @override
  Future<String?> enable() async {
    try {
      final settings = await _messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied ||
          settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        log('push permission ${settings.authorizationStatus.name}');
        return null;
      }
      // iOS: show nothing from FCM while the app is open; the in-app banner
      // (N-03a) does that.
      await _messaging.setForegroundNotificationPresentationOptions();
      return await _messaging.getToken(vapidKey: kIsWeb ? vapidKey : null);
    } catch (e) {
      // No APNs token yet (simulator), blocked browser, no Play services…
      log('push unavailable: $e');
      return null;
    }
  }

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Stream<PushTap> get taps => FirebaseMessaging.onMessageOpenedApp
      .map((m) => PushTap.fromData(m.data))
      .where((tap) => tap != null)
      .cast<PushTap>();

  @override
  Future<PushTap?> launchTap() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : PushTap.fromData(message.data);
  }

  @override
  Future<void> disable() async {
    try {
      await _messaging.deleteToken();
    } catch (e) {
      log('push token not deleted: $e');
    }
  }
}

/// Push not configured (no Firebase keys, tests): nothing to enable.
class NoPushService implements PushService {
  const NoPushService();

  @override
  String get platform => 'android';

  @override
  Future<String?> enable() async => null;

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();

  @override
  Stream<PushTap> get taps => const Stream.empty();

  @override
  Future<PushTap?> launchTap() async => null;

  @override
  Future<void> disable() async {}
}
