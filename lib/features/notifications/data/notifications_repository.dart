import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/log.dart';
import '../domain/app_notification.dart';
import '../domain/notification_prefs.dart';

/// The signed-in user's inbox (S-07), switches (S-08d) and devices.
/// Notifications are written only by the notify Edge Function.
abstract interface class NotificationsRepository {
  /// Newest first, the latest [inboxLimit]; updates live.
  Stream<List<AppNotification>> watchInbox(String userId);

  Future<void> markRead(String notificationId);

  /// Every unread row, or one tab's ([category]).
  Future<void> markAllRead({NotificationCategory? category});

  Future<NotificationPrefs> loadPrefs(String userId);
  Future<void> savePrefs(String userId, NotificationPrefs prefs);

  /// Links this device's FCM token to the user (moving it from whoever had
  /// it before).
  Future<void> registerDevice(String token, String platform);

  /// Unlinks the token; call while still signed in.
  Future<void> unregisterDevice(String token);

  /// Dev and staging: asks notify to send this user a `test` notification
  /// opening [target] (`inbox`, `order`, `quote`, `chat`) after [delay].
  Future<void> sendTest({
    String target = 'inbox',
    String? id,
    Duration delay = Duration.zero,
  });
}

/// How many rows the inbox keeps live.
const inboxLimit = 100;

class SupabaseNotificationsRepository implements NotificationsRepository {
  SupabaseNotificationsRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<List<AppNotification>> watchInbox(String userId) => _client
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('profile_id', userId)
      .order('created_at')
      .limit(inboxLimit)
      .map((rows) => rows.map(AppNotification.fromRow).toList());

  @override
  Future<void> markRead(String notificationId) => _client
      .from('notifications')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', notificationId)
      .isFilter('read_at', null);

  @override
  Future<void> markAllRead({NotificationCategory? category}) => _client.rpc(
    'mark_all_notifications_read',
    params: {'p_category': category?.name},
  );

  @override
  Future<NotificationPrefs> loadPrefs(String userId) async {
    final row = await _client
        .from('profiles')
        .select('notification_prefs')
        .eq('id', userId)
        .single();
    return NotificationPrefs.fromJson(row['notification_prefs']);
  }

  @override
  Future<void> savePrefs(String userId, NotificationPrefs prefs) => _client
      .from('profiles')
      .update({'notification_prefs': prefs.toJson()})
      .eq('id', userId);

  @override
  Future<void> registerDevice(String token, String platform) => _client.rpc(
    'register_device_token',
    params: {'p_token': token, 'p_platform': platform},
  );

  @override
  Future<void> unregisterDevice(String token) =>
      _client.from('device_tokens').delete().eq('token', token);

  @override
  Future<void> sendTest({
    String target = 'inbox',
    String? id,
    Duration delay = Duration.zero,
  }) async {
    final idKey = switch (target) {
      'order' => 'order_id',
      'quote' => 'rfq_id',
      'chat' => 'conversation_id',
      _ => null,
    };
    try {
      await _client.functions.invoke(
        'notify',
        body: {
          'type': 'test',
          'data': {
            'target': target,
            ?idKey: id,
            'delay_seconds': delay.inSeconds,
          },
        },
      );
    } catch (e) {
      log('notify test failed: $e');
      rethrow;
    }
  }
}

/// No backend: an empty inbox and default switches.
class OfflineNotificationsRepository implements NotificationsRepository {
  const OfflineNotificationsRepository();

  @override
  Stream<List<AppNotification>> watchInbox(String userId) =>
      Stream.value(const []);

  @override
  Future<void> markRead(String notificationId) async {}

  @override
  Future<void> markAllRead({NotificationCategory? category}) async {}

  @override
  Future<NotificationPrefs> loadPrefs(String userId) async =>
      const NotificationPrefs();

  @override
  Future<void> savePrefs(String userId, NotificationPrefs prefs) =>
      Future.error(StateError('Supabase not configured'));

  @override
  Future<void> registerDevice(String token, String platform) async {}

  @override
  Future<void> unregisterDevice(String token) async {}

  @override
  Future<void> sendTest({
    String target = 'inbox',
    String? id,
    Duration delay = Duration.zero,
  }) => Future.error(StateError('Supabase not configured'));
}
