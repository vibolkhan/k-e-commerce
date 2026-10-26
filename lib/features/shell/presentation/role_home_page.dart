import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/bootstrap.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_role.dart';
import '../../../core/ui/k_ui.dart';
import '../../auth/domain/auth_intent.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/require_sign_in.dart';
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
      appBar: AppBar(title: Text(l10n.roleHomeTitle(roleLabel(l10n, role)))),
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
          // Until the Account area (F06): Account › Sign in / Sign out.
          if (profile == null)
            Align(
              alignment: Alignment.centerLeft,
              child: KButton(
                label: l10n.authSignIn,
                icon: KIcons.account,
                onPressed: () =>
                    requireSignIn(context, ref, AuthIntent.account),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(l10n.authSignedInAs(profile.fullName ?? '')),
                ),
                KButton.outline(
                  label: l10n.authSignOut,
                  size: KButtonSize.sm,
                  onPressed: () => ref.read(authRepositoryProvider).signOut(),
                ),
              ],
            ),
          const SizedBox(height: 16),
          // Until the Account area (F06): live language switch and a sample
          // retail price in USD + KHR.
          if (role != AppRole.business) ...[
            const KPrice(cents: 4900),
            const SizedBox(height: 16),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: KButton.outline(
              label: l10n.languageTitle,
              icon: KIcons.language,
              onPressed: () => showLanguageSheet(context),
            ),
          ),
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
