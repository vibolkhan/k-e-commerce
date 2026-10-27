import 'package:k_e_commerce/core/router/app_role.dart';
import 'package:k_e_commerce/features/admin/data/admin_repository.dart';
import 'package:k_e_commerce/features/admin/domain/admin_section.dart';
import 'package:k_e_commerce/features/admin/domain/staff_member.dart';
import 'package:k_e_commerce/features/admin/domain/staff_outcome.dart';
import 'package:k_e_commerce/features/admin/domain/staff_role.dart';
import 'package:k_e_commerce/features/auth/domain/profile.dart';

/// 10:00 on Tue 27 Oct 2026 in Phnom Penh: 5 h before the 15:00 cut-off.
final adminNow = DateTime.utc(2026, 10, 27, 3);

/// The seeded staff (A-14d), one per role, plus a pending invite.
Profile staffProfile(
  String id,
  String name,
  StaffRole role, {
  StaffStatus status = StaffStatus.active,
  bool needsPassword = false,
}) => Profile(
  id: id,
  role: AppRole.admin,
  fullName: name,
  staffRole: role,
  staffStatus: status,
  needsPassword: needsPassword,
);

final staffAccounts = {
  'chenda@kstore.example': staffProfile(
    'u-chenda',
    'Chenda Lim',
    StaffRole.superAdmin,
  ),
  'dalin@kstore.example': staffProfile(
    'u-dalin',
    'Dalin Chhay',
    StaffRole.sales,
  ),
  'sophea@kstore.example': staffProfile(
    'u-sophea',
    'Sophea Mao',
    StaffRole.support,
  ),
  'visal@kstore.example': staffProfile(
    'u-visal',
    'Visal Keo',
    StaffRole.catalog,
  ),
  'rachana@kstore.example': staffProfile(
    'u-rachana',
    'Rachana Ty',
    StaffRole.support,
    status: StaffStatus.invited,
  ),
};

final seedStaff = [
  StaffMember(
    id: 'u-chenda',
    fullName: 'Chenda Lim',
    email: 'chenda@kstore.example',
    role: StaffRole.superAdmin,
    status: StaffStatus.active,
    lastSignInAt: adminNow,
    isMe: true,
  ),
  StaffMember(
    id: 'u-dalin',
    fullName: 'Dalin Chhay',
    email: 'dalin@kstore.example',
    role: StaffRole.sales,
    status: StaffStatus.active,
    lastSignInAt: adminNow.subtract(const Duration(minutes: 12)),
  ),
  StaffMember(
    id: 'u-sophea',
    fullName: 'Sophea Mao',
    email: 'sophea@kstore.example',
    role: StaffRole.support,
    status: StaffStatus.active,
    lastSignInAt: adminNow.subtract(const Duration(minutes: 3)),
  ),
  StaffMember(
    id: 'u-visal',
    fullName: 'Visal Keo',
    email: 'visal@kstore.example',
    role: StaffRole.catalog,
    status: StaffStatus.active,
    lastSignInAt: adminNow.subtract(const Duration(days: 1)),
  ),
  StaffMember(
    id: 'u-rachana',
    fullName: 'Rachana Ty',
    phone: '+85592115408',
    role: StaffRole.support,
    status: StaffStatus.invited,
    invitedAt: DateTime.utc(2026, 10, 21, 3),
    inviteExpiresAt: DateTime.utc(2026, 10, 28, 3),
  ),
];

/// Records every staff-manage call; [next] scripts the answer once.
class FakeAdminRepository implements AdminRepository {
  FakeAdminRepository({
    Map<AdminSection, int>? badges,
    List<StaffMember>? staff,
  }) : badges = badges ?? {},
       staff = staff ?? [...seedStaff];

  Map<AdminSection, int> badges;
  List<StaffMember> staff;
  StaffOutcome? next;
  final calls = <String>[];

  StaffOutcome _answer(String call, StaffAction done) {
    calls.add(call);
    final scripted = next;
    next = null;
    return scripted ?? StaffDone(done);
  }

  @override
  Future<Map<AdminSection, int>> badgeCounts() async => badges;

  @override
  Future<List<StaffMember>> staffDirectory() async => staff;

  @override
  Future<StaffOutcome> invite({
    required String fullName,
    required String contact,
    required StaffRole role,
  }) async =>
      _answer('invite $fullName $contact ${role.dbName}', StaffAction.invited);

  @override
  Future<StaffOutcome> resend(String profileId) async =>
      _answer('resend $profileId', StaffAction.resent);

  @override
  Future<StaffOutcome> updateRole(String profileId, StaffRole role) async =>
      _answer('update_role $profileId ${role.dbName}', StaffAction.updated);

  @override
  Future<StaffOutcome> remove(String profileId) async =>
      _answer('remove $profileId', StaffAction.removed);
}
