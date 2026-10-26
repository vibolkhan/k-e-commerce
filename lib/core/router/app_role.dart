import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_providers.dart';
import 'app_routes.dart';

/// Who is using the app; decides which shell they can open.
enum AppRole {
  customer(AppRoutes.customer),
  business(AppRoutes.business),
  rider(AppRoutes.rider),
  admin(AppRoutes.admin);

  const AppRole(this.homePath);

  final String homePath;
}

/// Current user's role, from their profile; guests browse as customers.
/// [set] overrides it until the profile changes (debug role switcher).
class CurrentRole extends Notifier<AppRole> {
  @override
  AppRole build() =>
      ref.watch(currentProfileProvider).value?.role ?? AppRole.customer;

  void set(AppRole role) => state = role;
}

final currentRoleProvider = NotifierProvider<CurrentRole, AppRole>(
  CurrentRole.new,
);
