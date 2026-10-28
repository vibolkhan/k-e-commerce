import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/khr_rate_provider.dart';
import '../../../core/router/app_role.dart';
import '../../../core/time/cutoff.dart';
import '../../../core/utils/log.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/admin_repository.dart';
import '../domain/admin_section.dart';
import '../domain/staff_member.dart';
import '../domain/staff_role.dart';

/// The staff role that decides the back-office menu and routes; null when
/// the account has no active staff membership (invite pending or expired,
/// removed, or not staff at all). The debug role switcher acts as a super
/// admin.
final currentStaffRoleProvider = Provider<StaffRole?>((ref) {
  if (ref.watch(currentRoleProvider) != AppRole.admin) return null;
  final profile = ref.watch(currentProfileProvider).value;
  if (profile == null || profile.role != AppRole.admin) {
    return StaffRole.superAdmin;
  }
  return profile.staffStatus == StaffStatus.active ? profile.staffRole : null;
});

/// How often the sidebar badges refresh while the back office is open
/// (`AdminShell`).
const badgeRefresh = Duration(seconds: 60);

/// Sidebar and bottom-nav counts.
final adminBadgesProvider = FutureProvider<Map<AdminSection, int>>((ref) async {
  ref.watch(currentStaffRoleProvider);
  try {
    return await ref.watch(adminRepositoryProvider).badgeCounts();
  } catch (e) {
    log('Could not load admin badges: $e');
    return const {};
  }
});

/// The cut-off from settings, [Cutoff.standard] until it loads.
final cutoffProvider = FutureProvider<Cutoff>((ref) async {
  try {
    return Cutoff.parse(
      await ref.watch(settingsRepositoryProvider).sameDayCutoff(),
    );
  } catch (e) {
    log('Could not load the cut-off, using 15:00: $e');
    return Cutoff.standard;
  }
});

/// A-14d staff list.
final staffDirectoryProvider = FutureProvider.autoDispose<List<StaffMember>>(
  (ref) => ref.watch(adminRepositoryProvider).staffDirectory(),
);
