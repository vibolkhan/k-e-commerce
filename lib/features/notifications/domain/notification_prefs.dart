/// The S-08d cards. Each turns off the push (and email) for its kind of
/// notification; payment, refund and account-security messages are always
/// sent, and everything still lands in the inbox.
enum NotificationGroup {
  orders(email: true),
  quotes(email: true),
  chat(email: false),
  reviews(email: false, pushByDefault: false);

  const NotificationGroup({required this.email, this.pushByDefault = true});

  /// Whether the card has an Email switch.
  final bool email;
  final bool pushByDefault;
}

enum NotificationChannel { push, email }

/// `profiles.notification_prefs`: `{"orders": {"push": true, "email": true},
/// …}`. A missing value means the default; keys this app doesn't know are
/// kept when saving. The notify Edge Function reads the same shape.
class NotificationPrefs {
  const NotificationPrefs([this._json = const {}]);

  factory NotificationPrefs.fromJson(Object? json) => NotificationPrefs(
    json is Map ? Map<String, Object?>.from(json) : const {},
  );

  final Map<String, Object?> _json;

  bool isOn(NotificationGroup group, NotificationChannel channel) {
    final saved = (_json[group.name] as Map?)?[channel.name];
    if (saved is bool) return saved;
    return channel == NotificationChannel.push ? group.pushByDefault : true;
  }

  NotificationPrefs withValue(
    NotificationGroup group,
    NotificationChannel channel,
    bool value,
  ) => NotificationPrefs({
    ..._json,
    group.name: {
      ...?(_json[group.name] as Map?)?.cast<String, Object?>(),
      channel.name: value,
    },
  });

  Map<String, Object?> toJson() => _json;
}
