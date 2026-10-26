import '../../../core/router/app_role.dart';

/// The signed-in user's `profiles` row — only what sign-in and routing need.
class Profile {
  const Profile({
    required this.id,
    required this.role,
    this.fullName,
    this.email,
    this.phone,
    this.isBlocked = false,
  });

  factory Profile.fromRow(Map<String, dynamic> row) => Profile(
    id: row['id'] as String,
    role: appRoleFor(row['role'] as String?),
    fullName: row['full_name'] as String?,
    email: row['email'] as String?,
    phone: row['phone'] as String?,
    isBlocked: row['is_blocked'] as bool? ?? false,
  );

  final String id;
  final AppRole role;
  final String? fullName;
  final String? email;
  final String? phone;
  final bool isBlocked;

  /// New users complete their name on S-06 before continuing.
  bool get needsName => (fullName ?? '').trim().isEmpty;
}

/// `user_role` in the database → app shell. Staff (any staff role) use the
/// admin back-office; anything unknown is treated as a customer.
AppRole appRoleFor(String? dbRole) => switch (dbRole) {
  'business' => AppRole.business,
  'rider' => AppRole.rider,
  'staff' => AppRole.admin,
  _ => AppRole.customer,
};
