import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_role.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/auth_outcome.dart';
import 'auth_providers.dart';

/// F08: staff invited by email arrive here from the invite link, already
/// signed in, and choose the password they'll use on S-04b from then on.
/// Phone invitees never see it; they sign in with a code.
class SetPasswordPage extends ConsumerStatefulWidget {
  const SetPasswordPage({super.key});

  static const minLength = 8;

  @override
  ConsumerState<SetPasswordPage> createState() => _SetPasswordPageState();
}

class _SetPasswordPageState extends ConsumerState<SetPasswordPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  var _busy = false;
  String? _passwordError;
  String? _confirmError;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final password = _password.text;
    setState(() {
      _passwordError = password.length < SetPasswordPage.minLength
          ? l10n.authPasswordTooShort(SetPasswordPage.minLength)
          : null;
      _confirmError = _passwordError == null && _confirm.text != password
          ? l10n.setPasswordMismatch
          : null;
    });
    if (_passwordError != null || _confirmError != null) return;

    setState(() => _busy = true);
    final outcome = await ref
        .read(authRepositoryProvider)
        .setPassword(password);
    if (!mounted) return;
    if (outcome is! SignedIn) {
      setState(() => _busy = false);
      showKToast(
        context,
        message: l10n.setPasswordFailed,
        tone: KToastTone.bad,
        icon: KIcons.error,
      );
      return;
    }
    // Reload so the router no longer sends this account back here.
    ref.invalidate(currentProfileProvider);
    await ref.read(currentProfileProvider.future);
    if (mounted) context.go(ref.read(currentRoleProvider).homePath);
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: KAppIcon(size: 48),
                ),
                const SizedBox(height: 24),
                Semantics(
                  header: true,
                  child: Text(l10n.setPasswordTitle, style: k.text.h1),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.setPasswordBody,
                  style: k.text.body.copyWith(color: c.muted),
                ),
                const SizedBox(height: 24),
                KTextField(
                  key: const Key('set-password'),
                  label: l10n.setPasswordLabel,
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  errorText: _passwordError,
                ),
                const SizedBox(height: 16),
                KTextField(
                  key: const Key('set-password-confirm'),
                  label: l10n.setPasswordConfirmLabel,
                  controller: _confirm,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  errorText: _confirmError,
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 24),
                KButton(
                  key: const Key('set-password-save'),
                  label: l10n.setPasswordSave,
                  size: KButtonSize.lg,
                  expand: true,
                  loading: _busy,
                  onPressed: _busy ? null : _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
