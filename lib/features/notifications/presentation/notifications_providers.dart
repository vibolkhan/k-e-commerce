import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/bootstrap.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/log.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/notifications_repository.dart';
import '../data/push_service.dart';
import '../domain/app_notification.dart';
import '../domain/notification_prefs.dart';

/// Supabase when configured; otherwise an empty offline inbox. Tests
/// override this.
final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  if (!ref.watch(appConfigProvider).isSupabaseConfigured) {
    return const OfflineNotificationsRepository();
  }
  return SupabaseNotificationsRepository(Supabase.instance.client);
});

/// FCM when Firebase started for this platform; otherwise no push.
final pushServiceProvider = Provider<PushService>((ref) {
  final config = ref.watch(appConfigProvider);
  if (!config.isPushConfigured || Firebase.apps.isEmpty) {
    return const NoPushService();
  }
  return FcmPushService(vapidKey: config.firebase.webVapidKey);
});

/// The signed-in user's inbox, newest first; empty for guests.
final inboxProvider = StreamProvider<List<AppNotification>>((ref) {
  final userId = ref.watch(authUserIdProvider).value;
  if (userId == null) return Stream.value(const []);
  return ref
      .watch(notificationsRepositoryProvider)
      .watchInbox(userId)
      .map(
        (rows) => [...rows]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );
});

/// Unread rows: the bell's red dot and the S-07 All count.
final unreadCountProvider = Provider<int>(
  (ref) => ref.watch(inboxProvider).value?.where((n) => n.isUnread).length ?? 0,
);

/// Marks a row read (S-07 tap, banner tap, push tap). Failing is harmless:
/// the row just stays unread.
Future<void> markReadQuietly(
  NotificationsRepository repo,
  String notificationId,
) async {
  try {
    await repo.markRead(notificationId);
  } catch (e) {
    log('mark read failed: $e');
  }
}

/// S-08d switches. Changes show at once and roll back if saving fails.
class NotificationPrefsController extends AsyncNotifier<NotificationPrefs> {
  @override
  Future<NotificationPrefs> build() async {
    final userId = await ref.watch(authUserIdProvider.future);
    if (userId == null) return const NotificationPrefs();
    return ref.watch(notificationsRepositoryProvider).loadPrefs(userId);
  }

  /// False when the change couldn't be saved (and was undone).
  Future<bool> set(
    NotificationGroup group,
    NotificationChannel channel,
    bool value,
  ) async {
    final userId = ref.read(authUserIdProvider).value;
    final before = state.value;
    if (userId == null || before == null) return false;
    final after = before.withValue(group, channel, value);
    state = AsyncData(after);
    try {
      await ref.read(notificationsRepositoryProvider).savePrefs(userId, after);
      return true;
    } catch (e) {
      log('save notification prefs failed: $e');
      // Undo only this switch, keeping any other change made meanwhile.
      final current = state.value ?? after;
      state = AsyncData(
        current.withValue(group, channel, before.isOn(group, channel)),
      );
      return false;
    }
  }
}

final notificationPrefsProvider =
    AsyncNotifierProvider<NotificationPrefsController, NotificationPrefs>(
      NotificationPrefsController.new,
    );

/// Links this device to whoever is signed in and opens tapped pushes.
/// Watched by `KApp` so it lives as long as the app.
class PushController {
  PushController(this._ref);

  final Ref _ref;
  final _subscriptions = <StreamSubscription<Object?>>[];
  String? _token;
  String? _userId;

  PushService get _push => _ref.read(pushServiceProvider);
  NotificationsRepository get _repo =>
      _ref.read(notificationsRepositoryProvider);

  void start() {
    _ref.listen(
      authUserIdProvider,
      (_, next) => _signedIn(next.value),
      fireImmediately: true,
    );
    _subscriptions
      ..add(_push.tokenRefreshes.listen(_register))
      ..add(_push.taps.listen(open));
    unawaited(_push.launchTap().then((tap) => tap == null ? null : open(tap)));
  }

  Future<void> _signedIn(String? userId) async {
    if (userId == _userId) return;
    _userId = userId;
    if (userId == null) {
      _token = null;
      return;
    }
    // Asks for permission the first time someone signs in on this device.
    final token = await _push.enable();
    if (token != null && _userId == userId) await _register(token);
  }

  Future<void> _register(String token) async {
    if (_userId == null) return;
    try {
      await _repo.registerDevice(token, _push.platform);
      _token = token;
    } catch (e) {
      log('device token not registered: $e');
    }
  }

  /// Before signing out, while the session can still delete the token.
  Future<void> signOut() async {
    final token = _token;
    _token = null;
    if (token == null) return;
    try {
      await _repo.unregisterDevice(token);
    } catch (e) {
      log('device token not removed: $e');
    }
    await _push.disable();
  }

  /// Opens a tapped push or banner and marks its inbox row read.
  Future<void> open(PushTap tap) async {
    final id = tap.notificationId;
    if (id != null && _userId != null) unawaited(markReadQuietly(_repo, id));
    _ref.read(routerProvider).go(tap.route);
  }

  void dispose() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
  }
}

final pushControllerProvider = Provider<PushController>((ref) {
  final controller = PushController(ref)..start();
  ref.onDispose(controller.dispose);
  return controller;
});
