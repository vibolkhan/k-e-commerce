import 'dart:async';

import 'package:k_e_commerce/features/notifications/data/notifications_repository.dart';
import 'package:k_e_commerce/features/notifications/data/push_service.dart';
import 'package:k_e_commerce/features/notifications/domain/app_notification.dart';
import 'package:k_e_commerce/features/notifications/domain/notification_prefs.dart';

/// In-memory twin of `notifications`, `notification_prefs` and
/// `device_tokens` for one user, with live updates like Realtime.
class FakeNotificationsRepository implements NotificationsRepository {
  FakeNotificationsRepository([List<AppNotification> rows = const []])
    : rows = [...rows];

  List<AppNotification> rows;
  NotificationPrefs prefs = const NotificationPrefs();
  final _changes = StreamController<List<AppNotification>>.broadcast();

  /// token → platform.
  final devices = <String, String>{};
  final read = <String>[];
  final tests = <({String target, String? id, Duration delay})>[];
  var markAllCalls = 0;

  /// Makes the next savePrefs / markAllRead fail.
  bool failSave = false;
  bool failMarkAll = false;

  /// The notify Edge Function writing a row while the app is open.
  void deliver(AppNotification n) {
    rows = [n, ...rows];
    _changes.add(rows);
  }

  void _emit() => _changes.add(rows);

  @override
  Stream<List<AppNotification>> watchInbox(String userId) async* {
    yield rows;
    yield* _changes.stream;
  }

  @override
  Future<void> markRead(String notificationId) async {
    read.add(notificationId);
    final at = DateTime.now();
    rows = [
      for (final n in rows) n.id == notificationId ? n.markedRead(at) : n,
    ];
    _emit();
  }

  @override
  Future<void> markAllRead({NotificationCategory? category}) async {
    markAllCalls++;
    if (failMarkAll) throw StateError('offline');
    final at = DateTime.now();
    rows = [
      for (final n in rows)
        category == null || n.category == category ? n.markedRead(at) : n,
    ];
    _emit();
  }

  @override
  Future<NotificationPrefs> loadPrefs(String userId) async => prefs;

  @override
  Future<void> savePrefs(String userId, NotificationPrefs prefs) async {
    if (failSave) throw StateError('offline');
    this.prefs = prefs;
  }

  @override
  Future<void> registerDevice(String token, String platform) async =>
      devices[token] = platform;

  @override
  Future<void> unregisterDevice(String token) async => devices.remove(token);

  @override
  Future<void> sendTest({
    String target = 'inbox',
    String? id,
    Duration delay = Duration.zero,
  }) async => tests.add((target: target, id: id, delay: delay));

  void dispose() => _changes.close();
}

/// FCM on a device: a token after permission, taps the test sends.
class FakePushService implements PushService {
  FakePushService({this.token = 'fcm-token-1', this.launch});

  /// Null = permission refused.
  String? token;

  /// The push that "launched" the app.
  PushTap? launch;
  var disabled = 0;
  var enabled = 0;

  final _taps = StreamController<PushTap>.broadcast();
  final _refreshes = StreamController<String>.broadcast();

  void tap(PushTap tap) => _taps.add(tap);
  void rotate(String token) => _refreshes.add(this.token = token);

  @override
  String get platform => 'android';

  @override
  Future<String?> enable() async {
    enabled++;
    return token;
  }

  @override
  Stream<String> get tokenRefreshes => _refreshes.stream;

  @override
  Stream<PushTap> get taps => _taps.stream;

  @override
  Future<PushTap?> launchTap() async {
    final tap = launch;
    launch = null;
    return tap;
  }

  @override
  Future<void> disable() async => disabled++;

  void dispose() {
    _taps.close();
    _refreshes.close();
  }
}

const orderId = 'd0000000-0000-4000-8000-000000010248';
const rfqId = 'b0000000-0000-4000-8000-000000000312';
const conversationId = '91000000-0000-4000-8000-000000000001';

/// A row as the notify Edge Function writes it.
AppNotification notification(
  String id, {
  String type = 'order_out_for_delivery',
  NotificationCategory category = NotificationCategory.orders,
  String title = 'Your order is on the way',
  String body = 'Vuthy is delivering #K-10248. Arriving in about 18 min.',
  String? route = '/customer/orders/$orderId',
  required DateTime at,
  bool read = false,
}) => AppNotification(
  id: id,
  type: type,
  category: category,
  title: {'en': title, 'km': 'KM $title'},
  body: {'en': body, 'km': 'KM $body'},
  route: route,
  createdAt: at,
  readAt: read ? at : null,
);
