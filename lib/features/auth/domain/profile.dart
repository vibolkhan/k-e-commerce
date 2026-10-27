import '../../../core/router/app_role.dart';
import '../../admin/domain/staff_role.dart';

/// The signed-in user's `profiles` row — only what sign-in and routing need.
class Profile {
  const Profile({
    required this.id,
    required this.role,
    this.fullName,
    this.email,
    this.phone,
    this.isBlocked = false,
    this.staffRole,
    this.staffStatus,
    this.needsPassword = false,
  });

  /// A `profiles` row with its embedded `staff_members(staff_role, status)`.
  /// [needsPassword] comes from the auth user's metadata.
  factory Profile.fromRow(
    Map<String, dynamic> row, {
    bool needsPassword = false,
  }) {
    final staff = switch (row['staff_members']) {
      final Map<String, dynamic> one => one,
      [final Map<String, dynamic> one, ...] => one,
      _ => null,
    };
    return Profile(
      id: row['id'] as String,
      role: appRoleFor(row['role'] as String?),
      fullName: row['full_name'] as String?,
      email: row['email'] as String?,
      phone: row['phone'] as String?,
      isBlocked: row['is_blocked'] as bool? ?? false,
      staffRole: StaffRole.fromDb(staff?['staff_role'] as String?),
      staffStatus: StaffStatus.fromDb(staff?['status'] as String?),
      needsPassword: needsPassword,
    );
  }

  final String id;
  final AppRole role;
  final String? fullName;
  final String? email;
  final String? phone;
  final bool isBlocked;

  /// Staff only (F08): what they can open, and whether they can yet.
  final StaffRole? staffRole;
  final StaffStatus? staffStatus;

  /// Invited by email and hasn't set a password yet.
  final bool needsPassword;

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
