import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Current user's role. Placeholder until sign-in (F05/F06) resolves the role
/// from the Supabase session.
class CurrentRole extends Notifier<AppRole> {
  @override
  AppRole build() => AppRole.customer;

  void set(AppRole role) => state = role;
}

final currentRoleProvider = NotifierProvider<CurrentRole, AppRole>(
  CurrentRole.new,
);
