import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/bootstrap.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_role.dart';
import '../../../core/ui/k_ui.dart';
import '../../account/presentation/account_actions.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../../settings/presentation/language_sheet.dart';

/// Placeholder home for each role's shell until its real screens are built.
class RoleHomePage extends ConsumerWidget {
  const RoleHomePage({super.key, required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(appConfigProvider);
    final profile = ref.watch(currentProfileProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.roleHomeTitle(roleLabel(l10n, role))),
        // C-01 / B-00 header bell; riders and staff get theirs with F21/F37.
        actions: [
          if (profile != null && role.hasAccountTab) ...[
            NotificationBell(shell: role.homePath),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.shellPlaceholder),
          if (!config.isSupabaseConfigured) ...[
            const SizedBox(height: 8),
            Text(
              l10n.supabaseNotConfigured,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          if (role != AppRole.business) ...[
            const KPrice(cents: 4900),
            const SizedBox(height: 16),
          ],
          // Customers and business buyers have the Account tab (S-08). Until
          // the rider and admin apps get theirs: language and sign out.
          if (!role.hasAccountTab) ...[
            if (profile != null) ...[
              Text(l10n.authSignedInAs(profile.fullName ?? '')),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                KButton.outline(
                  label: l10n.languageTitle,
                  icon: KIcons.language,
                  onPressed: () => showLanguageSheet(context),
                ),
                if (profile != null)
                  KButton.outline(
                    label: l10n.authSignOut,
                    onPressed: () => confirmSignOut(context, ref),
                  ),
              ],
            ),
          ],
          if (kDebugMode) ...[
            const SizedBox(height: 24),
            Text(l10n.devRoleSwitcher),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final r in AppRole.values)
                  ChoiceChip(
                    label: Text(roleLabel(l10n, r)),
                    selected: r == role,
                    onSelected: (_) =>
                        ref.read(currentRoleProvider.notifier).set(r),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String roleLabel(AppLocalizations l10n, AppRole role) => switch (role) {
  AppRole.customer => l10n.roleCustomer,
  AppRole.business => l10n.roleBusiness,
  AppRole.rider => l10n.roleRider,
  AppRole.admin => l10n.roleAdmin,
};
