import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/supported_languages.dart';
import '../../../core/router/app_role.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/ui/k_ui.dart';
import '../../auth/domain/auth_intent.dart';
import '../../auth/domain/phone_number.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/require_sign_in.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../../settings/presentation/language_sheet.dart';
import 'account_actions.dart';

/// Account tab of the customer and business shells: S-08 when signed in,
/// S-08a for guests.
class AccountPage extends ConsumerWidget {
  const AccountPage({super.key, required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).value;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: profile == null
            ? const _GuestAccount()
            : _SignedInAccount(profile: profile, role: role),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.child, this.shell});

  final Widget? child;

  /// Shows the S-07 bell for this shell (signed in only).
  final String? shell;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Container(
      decoration: BoxDecoration(
        color: k.colors.surface,
        border: Border(bottom: BorderSide(color: k.colors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: kMinTap,
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      AppLocalizations.of(context).accountTitle,
                      style: k.text.h2.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                if (shell != null) NotificationBell(shell: shell!),
              ],
            ),
          ),
          if (child != null) ...[const SizedBox(height: 12), child!],
        ],
      ),
    );
  }
}

/// S-08a: sign-in prompt, plus the settings a guest can change.
class _GuestAccount extends ConsumerWidget {
  const _GuestAccount();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    void signIn() => requireSignIn(context, ref, AuthIntent.account);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              KCard(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: c.tint2,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: KIcon(
                        KIcons.account,
                        size: 32,
                        color: c.primaryInk,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.accountGuestTitle,
                        textAlign: TextAlign.center,
                        style: k.text.title,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.accountGuestBody,
                      textAlign: TextAlign.center,
                      style: k.text.small.copyWith(color: c.muted),
                    ),
                    const SizedBox(height: 16),
                    KButton(
                      key: const Key('account-sign-in'),
                      label: l10n.authSignIn,
                      size: KButtonSize.lg,
                      expand: true,
                      onPressed: signIn,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.center,
                      children: [
                        Text(
                          l10n.accountGuestNew,
                          style: k.text.small.copyWith(color: c.ink2),
                        ),
                        KButton.ghost(
                          label: l10n.authCreateAccount,
                          size: KButtonSize.sm,
                          onPressed: signIn,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              KCard(
                padding: EdgeInsets.zero,
                clip: true,
                child: KList(
                  children: [
                    const _LanguageRow(),
                    KListRow(
                      title: l10n.accountHelp,
                      icon: KIcons.help,
                      onTap: () => showComingSoon(context),
                    ),
                    KListRow(
                      title: l10n.accountTerms,
                      icon: KIcons.info,
                      onTap: () => showComingSoon(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// S-08: profile header, activity, settings, sign out and delete.
class _SignedInAccount extends ConsumerWidget {
  const _SignedInAccount({required this.profile, required this.role});

  final Profile profile;
  final AppRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    void soon() => showComingSoon(context);
    final phone = profile.phone;
    final contact = phone != null ? KhPhone.display(phone) : profile.email;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          shell: role.homePath,
          child: Row(
            children: [
              SizedBox.square(
                dimension: 52,
                child: FittedBox(
                  child: KAvatar(
                    initialsOf(profile.fullName),
                    size: KAvatarSize.lg,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.fullName ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: k.text.h3,
                    ),
                    if (contact != null)
                      Text(
                        contact,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: k.text.small.copyWith(color: c.muted),
                      ),
                  ],
                ),
              ),
              KButton.outline(
                key: const Key('account-edit'),
                label: l10n.accountEdit,
                size: KButtonSize.sm,
                onPressed: () =>
                    context.push(AppRoutes.accountEdit(role.homePath)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            children: [
              if (role == AppRole.customer) ...[
                KCard(
                  style: KCardStyle.tint,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  onTap: soon,
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(KRadius.input),
                        ),
                        alignment: Alignment.center,
                        child: KIcon(
                          KIcons.business,
                          size: 20,
                          color: c.primaryInk,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.accountBusinessTitle,
                              style: k.text.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              l10n.accountBusinessAction,
                              style: k.text.small.copyWith(color: c.ink3),
                            ),
                          ],
                        ),
                      ),
                      KIcon(KIcons.chevronRight, size: 20, color: c.muted),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _Section(
                title: l10n.accountActivity,
                rows: [
                  KListRow(
                    title: l10n.accountOrders,
                    icon: KIcons.orders,
                    onTap: soon,
                  ),
                  KListRow(
                    title: l10n.accountWishlist,
                    icon: KIcons.heart,
                    onTap: soon,
                  ),
                  KListRow(
                    title: l10n.accountReturns,
                    icon: KIcons.returnItem,
                    onTap: soon,
                  ),
                  KListRow(
                    key: const Key('account-addresses'),
                    title: l10n.accountAddresses,
                    icon: KIcons.location,
                    onTap: () =>
                        context.push(AppRoutes.addresses(role.homePath)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Section(
                title: l10n.accountSettings,
                rows: [
                  const _LanguageRow(),
                  KListRow(
                    key: const Key('account-notifications'),
                    title: l10n.accountNotifications,
                    icon: KIcons.notifications,
                    onTap: () => context.push(
                      AppRoutes.accountNotifications(role.homePath),
                    ),
                  ),
                  KListRow(
                    title: l10n.accountHelp,
                    icon: KIcons.help,
                    onTap: soon,
                  ),
                  KListRow(
                    title: l10n.accountTerms,
                    icon: KIcons.info,
                    onTap: soon,
                  ),
                  _SignOutRow(onTap: () => confirmSignOut(context, ref)),
                ],
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  key: const Key('account-delete'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(kMinTap, kMinTap),
                    foregroundColor: c.ink3,
                    textStyle: k.text.small.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  onPressed: () =>
                      context.push(AppRoutes.accountDelete(role.homePath)),
                  child: Text(l10n.accountDelete),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(header: true, child: KOverline(title)),
        ),
        const SizedBox(height: 6),
        KCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: KList(children: rows),
        ),
      ],
    );
  }
}

/// Language row with the current language; opens S-08c.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow();

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final current = appLanguageFor(
      Localizations.localeOf(context).languageCode,
    );
    return KListRow(
      key: const Key('account-language'),
      title: l10n.languageTitle,
      icon: KIcons.language,
      trailing: current == null
          ? null
          : Text(
              current.name(l10n),
              style: k.text.small.copyWith(color: k.colors.muted),
            ),
      showChevron: true,
      onTap: () => showLanguageSheet(context),
    );
  }
}

class _SignOutRow extends StatelessWidget {
  const _SignOutRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    return Material(
      color: c.surface,
      child: InkWell(
        key: const Key('account-sign-out'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.badBg,
                    borderRadius: BorderRadius.circular(KRadius.input),
                  ),
                  alignment: Alignment.center,
                  child: KIcon(KIcons.back, size: 20, color: c.bad),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).authSignOut,
                    style: context.k.text.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: c.bad,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
