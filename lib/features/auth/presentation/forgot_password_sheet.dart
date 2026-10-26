import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/auth_outcome.dart';
import '../domain/phone_number.dart';
import 'auth_providers.dart';

/// "Forgot password?" on S-04b: sends Supabase's reset email. The reply is
/// the same for unknown emails so the sheet can't be used to probe accounts.
Future<void> showForgotPasswordSheet(
  BuildContext context, {
  String initialEmail = '',
}) {
  final l10n = AppLocalizations.of(context);
  return showKBottomSheet<void>(
    context,
    title: l10n.authResetTitle,
    builder: (_) => _ForgotPasswordForm(initialEmail: initialEmail),
  );
}

class _ForgotPasswordForm extends ConsumerStatefulWidget {
  const _ForgotPasswordForm({required this.initialEmail});

  final String initialEmail;

  @override
  ConsumerState<_ForgotPasswordForm> createState() =>
      _ForgotPasswordFormState();
}

class _ForgotPasswordFormState extends ConsumerState<_ForgotPasswordForm> {
  late final _email = TextEditingController(text: widget.initialEmail);
  String? _error;
  var _busy = false;
  var _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final email = normalizeEmail(_email.text);
    if (email == null) {
      setState(() => _error = l10n.authEmailInvalid);
      return;
    }
    setState(() => _busy = true);
    final outcome = await ref.read(authRepositoryProvider).resetPassword(email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sent = outcome is! AuthFailure;
      _error = _sent ? null : l10n.authNetworkError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.authResetBody,
          style: k.text.body.copyWith(color: k.colors.ink2),
        ),
        const SizedBox(height: 16),
        if (_sent)
          KBanner(message: l10n.authResetSent, tone: KBannerTone.ok)
        else ...[
          KTextField(
            key: const Key('reset-email'),
            label: l10n.authEmailLabel,
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            errorText: _error,
            onSubmitted: (_) => _send(),
          ),
          const SizedBox(height: 16),
          KButton(
            label: l10n.authResetSend,
            expand: true,
            loading: _busy,
            onPressed: _busy ? null : _send,
          ),
        ],
      ],
    );
  }
}
