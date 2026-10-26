import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_role.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/phone_number.dart';
import 'auth_flow.dart';
import 'auth_providers.dart';

/// S-06: new users give the name used on orders, receipts and delivery
/// labels, plus an optional receipts email. No way back — the account
/// exists already and needs a name before it can continue.
class CompleteProfilePage extends ConsumerStatefulWidget {
  const CompleteProfilePage({super.key});

  @override
  ConsumerState<CompleteProfilePage> createState() =>
      _CompleteProfilePageState();
}

class _CompleteProfilePageState extends ConsumerState<CompleteProfilePage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  var _receipts = true;
  var _busy = false;
  String? _nameError;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    // Prefill what sign-in already knows (email sign-ups, Google).
    ref.read(currentProfileProvider.future).then((profile) {
      if (!mounted || profile == null) return;
      if (_name.text.isEmpty) _name.text = profile.fullName ?? '';
      if (_email.text.isEmpty) _email.text = profile.email ?? '';
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    final rawEmail = _email.text.trim();
    final email = rawEmail.isEmpty ? null : normalizeEmail(rawEmail);
    setState(() {
      _nameError = name.isEmpty ? l10n.authFullNameRequired : null;
      _emailError = rawEmail.isNotEmpty && email == null
          ? l10n.authEmailInvalid
          : null;
    });
    if (_nameError != null || _emailError != null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .completeProfile(
            fullName: name,
            email: email,
            emailReceipts: _receipts && email != null,
          );
      // Reload before leaving so the router doesn't send us back here
      // from a stale "no name" profile.
      ref.invalidate(currentProfileProvider);
      await ref.read(currentProfileProvider.future);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showKToast(
          context,
          message: l10n.authNetworkError,
          tone: KToastTone.bad,
        );
      }
      return;
    }
    if (!mounted) return;
    if (context.canPop()) {
      context.pop(AuthStepResult.done);
    } else {
      context.go(ref.read(currentRoleProvider).homePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: c.surface,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            children: [
              Text(
                l10n.authProfileProgress,
                style: k.text.caption.copyWith(color: c.muted),
              ),
              const SizedBox(height: 8),
              Semantics(
                label: l10n.authProfileProgressLabel,
                value: '90%',
                child: const KProgressBar(value: 0.9),
              ),
              const SizedBox(height: 24),
              Semantics(
                header: true,
                child: Text(l10n.authProfileTitle, style: k.text.h1),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.authProfileSubtitle,
                style: k.text.body.copyWith(color: c.muted),
              ),
              const SizedBox(height: 24),
              KTextField(
                key: const Key('profile-name'),
                label: l10n.authFullName,
                controller: _name,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                errorText: _nameError,
                onChanged: (_) {
                  if (_nameError != null) setState(() => _nameError = null);
                },
              ),
              const SizedBox(height: 16),
              KTextField(
                key: const Key('profile-email'),
                label: l10n.authEmailLabel,
                optional: true,
                controller: _email,
                hint: 'name@example.com',
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                helpText: l10n.authProfileEmailHelp,
                errorText: _emailError,
                onChanged: (_) {
                  if (_emailError != null) setState(() => _emailError = null);
                },
              ),
              const SizedBox(height: 8),
              KSwitchRow(
                label: l10n.authEmailReceipts,
                value: _receipts,
                onChanged: (v) => setState(() => _receipts = v),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: KButton(
              key: const Key('profile-continue'),
              label: l10n.uiContinue,
              size: KButtonSize.lg,
              expand: true,
              loading: _busy,
              onPressed: _busy ? null : _save,
            ),
          ),
        ),
      ),
    );
  }
}
