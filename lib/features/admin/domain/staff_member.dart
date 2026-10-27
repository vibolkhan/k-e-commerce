import 'staff_role.dart';

/// One row of the A-14d staff list (`staff_directory()`).
class StaffMember {
  const StaffMember({
    required this.id,
    required this.role,
    required this.status,
    this.fullName,
    this.email,
    this.phone,
    this.lastSignInAt,
    this.invitedAt,
    this.inviteExpiresAt,
    this.isMe = false,
  });

  factory StaffMember.fromRow(Map<String, dynamic> row) => StaffMember(
    id: row['profile_id'] as String,
    role: StaffRole.fromDb(row['staff_role'] as String?) ?? StaffRole.support,
    status: StaffStatus.fromDb(row['status'] as String?) ?? StaffStatus.invited,
    fullName: row['full_name'] as String?,
    email: row['email'] as String?,
    phone: row['phone'] as String?,
    lastSignInAt: _date(row['last_sign_in_at']),
    invitedAt: _date(row['invited_at']),
    inviteExpiresAt: _date(row['invite_expires_at']),
    isMe: row['is_me'] as bool? ?? false,
  );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  final String id;
  final StaffRole role;
  final StaffStatus status;
  final String? fullName;
  final String? email;
  final String? phone;
  final DateTime? lastSignInAt;
  final DateTime? invitedAt;
  final DateTime? inviteExpiresAt;

  /// The signed-in super admin ("you"); they can't edit themselves.
  final bool isMe;

  bool get isPending => status == StaffStatus.invited;

  /// The invite can no longer be accepted; Resend issues a new one.
  bool isExpired(DateTime now) =>
      isPending && inviteExpiresAt != null && !inviteExpiresAt!.isAfter(now);

  /// What the row shows under the name: the email, else the phone.
  String get contact => email ?? phone ?? '';
}
