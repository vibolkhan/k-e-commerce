/// S-07 tab a notification belongs to (`notifications.category`).
/// `account` (business verification, tests) shows under All only.
enum NotificationCategory {
  orders,
  quotes,
  chat,
  account;

  static NotificationCategory parse(String? value) => values.firstWhere(
    (c) => c.name == value,
    orElse: () => NotificationCategory.orders,
  );
}

/// The tabs on S-07, in order.
enum InboxTab {
  all(null),
  orders(NotificationCategory.orders),
  quotes(NotificationCategory.quotes),
  chat(NotificationCategory.chat);

  const InboxTab(this.category);

  /// Null for All.
  final NotificationCategory? category;

  bool shows(AppNotification n) => category == null || n.category == category;
}

/// One inbox row (`notifications`). Copy is stored per language, as the
/// notify Edge Function wrote it.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.category,
    required this.title,
    required this.body,
    required this.createdAt,
    this.route,
    this.readAt,
  });

  factory AppNotification.fromRow(Map<String, dynamic> row) {
    final payload = (row['payload'] as Map?) ?? const {};
    return AppNotification(
      id: row['id'] as String,
      type: row['type'] as String,
      category: NotificationCategory.parse(row['category'] as String?),
      title: _texts(row['title']),
      body: _texts(row['body']),
      route: safeRoute(payload['route']),
      createdAt: DateTime.parse(row['created_at'] as String),
      readAt: row['read_at'] == null
          ? null
          : DateTime.parse(row['read_at'] as String),
    );
  }

  final String id;
  final String type;
  final NotificationCategory category;
  final Map<String, String> title;
  final Map<String, String> body;

  /// In-app path a tap opens; null when there is nowhere to go.
  final String? route;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  /// Copy in [languageCode], falling back to English, then any language.
  String titleIn(String languageCode) => _pick(title, languageCode);
  String bodyIn(String languageCode) => _pick(body, languageCode);

  AppNotification markedRead(DateTime at) => AppNotification(
    id: id,
    type: type,
    category: category,
    title: title,
    body: body,
    route: route,
    createdAt: createdAt,
    readAt: readAt ?? at,
  );

  static Map<String, String> _texts(Object? value) => {
    if (value is Map)
      for (final e in value.entries)
        if (e.value is String) '${e.key}': e.value as String,
  };

  static String _pick(Map<String, String> texts, String languageCode) =>
      texts[languageCode] ?? texts['en'] ?? texts.values.firstOrNull ?? '';
}

/// [value] if it is an in-app path (`/…`, not `//host`); otherwise null.
/// Pushes and inbox rows carry routes, and only paths may reach the router.
String? safeRoute(Object? value) {
  if (value is! String) return null;
  if (!value.startsWith('/') || value.startsWith('//')) return null;
  return Uri.tryParse(value) == null ? null : value;
}
