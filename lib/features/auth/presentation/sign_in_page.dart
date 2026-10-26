import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_role.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/time/date_format.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/auth_intent.dart';
import '../domain/auth_outcome.dart';
import '../domain/phone_number.dart';
import 'auth_dialogs.dart';
import 'auth_flow.dart';
import 'auth_providers.dart';
import 'forgot_password_sheet.dart';

enum SignInMethod { phone, email }

/// S-04 / S-04b: phone (default), email + password, Google and Apple.
/// Pops `true` once signed in; when nothing is underneath (opened by link)
/// it goes to [from] or the role's home instead.
class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key, this.intent, this.from, this.blocked = false});

  final AuthIntent? intent;
  final String? from;

  /// Arrived because a blocked account was signed in: show S-06b.
  final bool blocked;

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

enum _Busy { none, phone, email, google, apple }

class _SignInPageState extends ConsumerState<SignInPage> {
  var _method = SignInMethod.phone;
  var _busy = _Busy.none;
  var _creatingAccount = false;
  var _obscure = true;
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _phoneError;
  String? _emailError;
  String? _passwordError;
  String? _notice;

  // Browser OAuth left the app; finish when the session shows up.
  var _awaitingRedirect = false;

  @override
  void initState() {
    super.initState();
    if (widget.blocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await ref.read(authRepositoryProvider).signOut();
        if (mounted) await showBlockedDialog(context, ref);
      });
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context);

  void _finish() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop(true);
    } else {
      context.go(
        safeReturnPath(widget.from) ?? ref.read(currentRoleProvider).homePath,
      );
    }
  }

  Future<void> _signedIn(SignedIn outcome) async {
    if (await completeSignIn(context, isNewUser: outcome.isNewUser)) {
      _finish();
    }
  }

  Future<void> _run(_Busy which, Future<void> Function() body) async {
    if (_busy != _Busy.none) return;
    setState(() {
      _busy = which;
      _notice = null;
    });
    try {
      await body();
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  void _failed() => showKToast(
    context,
    message: _l10n.authNetworkError,
    tone: KToastTone.bad,
  );

  // ----------------------------------------------------------------- phone

  Future<void> _continueWithPhone() async {
    final phone = KhPhone.normalize(_phone.text);
    if (phone == null) {
      setState(() => _phoneError = _l10n.authPhoneInvalid);
      return;
    }
    await _run(_Busy.phone, () async {
      final outcome = await ref.read(authRepositoryProvider).sendOtp(phone);
      if (!mounted) return;
      switch (outcome) {
        case OtpSent(:final resendIn) || ResendTooSoon(:final resendIn):
          await _openOtp(phone, resendIn);
        case Locked():
          if (await showLockedDialog(context, ref, outcome, viaPhone: true)) {
            _switchTo(SignInMethod.email);
          }
        case Blocked():
          await showBlockedDialog(context, ref);
        case SendFailed():
          setState(() => _phoneError = _l10n.authSendFailed);
        default:
          _failed();
      }
    });
  }

  Future<void> _openOtp(String phone, Duration resendIn) async {
    final result = await context.push<AuthStepResult>(
      AppRoutes.signInVerifyFor(phone),
      extra: resendIn,
    );
    if (!mounted) return;
    switch (result) {
      case AuthStepResult.done:
        _finish();
      case AuthStepResult.useEmail:
        _switchTo(SignInMethod.email);
      case null:
        break;
    }
  }

  // ----------------------------------------------------------------- email

  Future<void> _submitEmail() async {
    final email = normalizeEmail(_email.text);
    final password = _password.text;
    setState(() {
      _emailError = email == null ? _l10n.authEmailInvalid : null;
      _passwordError = password.isEmpty
          ? _l10n.authPasswordRequired
          : (_creatingAccount && password.length < minPasswordLength)
          ? _l10n.authPasswordTooShort(minPasswordLength)
          : null;
    });
    if (email == null || _passwordError != null) return;

    await _run(_Busy.email, () async {
      final repo = ref.read(authRepositoryProvider);
      final outcome = _creatingAccount
          ? await repo.signUpWithPassword(email, password)
          : await repo.signInWithPassword(email, password);
      if (!mounted) return;
      switch (outcome) {
        case SignedIn():
          await _signedIn(outcome);
        case WrongCredentials(:final triesLeft):
          setState(() => _passwordError = _l10n.authWrongPassword(triesLeft));
        case Locked(:final until):
          setState(
            () => _passwordError = _l10n.authLockedInline(
              formatTime(_l10n, until),
            ),
          );
          if (await showLockedDialog(context, ref, outcome, viaPhone: false)) {
            _switchTo(SignInMethod.phone);
          }
        case Blocked():
          await showBlockedDialog(context, ref);
        case ConfirmEmail():
          setState(() => _notice = _l10n.authConfirmEmail);
        case EmailInUse():
          setState(() => _emailError = _l10n.authEmailInUse);
        default:
          _failed();
      }
    });
  }

  // ---------------------------------------------------------------- social

  Future<void> _social(_Busy which) async {
    await _run(which, () async {
      final repo = ref.read(authRepositoryProvider);
      final outcome = which == _Busy.google
          ? await repo.signInWithGoogle()
          : await repo.signInWithApple();
      if (!mounted) return;
      switch (outcome) {
        case SignedIn():
          await _signedIn(outcome);
        case Redirecting():
          _awaitingRedirect = true;
        case Blocked():
          await showBlockedDialog(context, ref);
        case Cancelled():
          break;
        default:
          showKToast(
            context,
            message: _l10n.authSocialFailed,
            tone: KToastTone.bad,
          );
      }
    });
  }

  Future<void> _resumeAfterRedirect() async {
    _awaitingRedirect = false;
    final profile = await ref.read(currentProfileProvider.future);
    if (!mounted || profile == null) return;
    if (profile.isBlocked) {
      await ref.read(authRepositoryProvider).signOut();
      if (mounted) await showBlockedDialog(context, ref);
      return;
    }
    await _signedIn(SignedIn(isNewUser: profile.needsName));
  }

  void _switchTo(SignInMethod method) => setState(() {
    _method = method;
    _phoneError = null;
    _emailError = null;
    _passwordError = null;
    _notice = null;
  });

  Future<void> _forgotPassword() =>
      showForgotPasswordSheet(context, initialEmail: _email.text);

  @override
  Widget build(BuildContext context) {
    ref.listen(authUserIdProvider, (previous, next) {
      if (_awaitingRedirect && next.value != null) _resumeAfterRedirect();
    });
    final k = context.k;
    final l10n = _l10n;
    final busy = _busy != _Busy.none;

    return Scaffold(
      backgroundColor: k.colors.surface,
      appBar: AuthTopBar(
        close: true,
        onPressed: () => context.canPop()
            ? context.pop(false)
            : context.go(
                safeReturnPath(widget.from) ??
                    ref.read(currentRoleProvider).homePath,
              ),
      ),
      body: SafeArea(
        top: false,
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              Semantics(
                header: true,
                child: Text(l10n.authSignInTitle, style: k.text.h1),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.authSignInSubtitle,
                style: k.text.body.copyWith(color: k.colors.muted),
              ),
              const SizedBox(height: 24),
              Semantics(
                label: l10n.authMethodLabel,
                child: KSegmented<SignInMethod>(
                  segments: [
                    KSegment(SignInMethod.phone, l10n.authMethodPhone),
                    KSegment(SignInMethod.email, l10n.authMethodEmail),
                  ],
                  selected: _method,
                  onChanged: busy ? (_) {} : _switchTo,
                ),
              ),
              const SizedBox(height: 24),
              if (_method == SignInMethod.phone)
                ..._phoneForm(l10n)
              else
                ..._emailForm(l10n, k),
              if (_method == SignInMethod.phone) ...[
                const SizedBox(height: 24),
                _OrDivider(label: l10n.authOr),
                const SizedBox(height: 24),
                KSocialButton(
                  provider: KSocialProvider.google,
                  label: l10n.authContinueWithGoogle,
                  loading: _busy == _Busy.google,
                  onPressed: busy ? null : () => _social(_Busy.google),
                ),
                const SizedBox(height: 12),
                KSocialButton(
                  provider: KSocialProvider.apple,
                  label: l10n.authContinueWithApple,
                  loading: _busy == _Busy.apple,
                  onPressed: busy ? null : () => _social(_Busy.apple),
                ),
              ],
              const SizedBox(height: 32),
              _LegalFooter(l10n: l10n),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _phoneForm(AppLocalizations l10n) => [
    KTextField(
      key: const Key('sign-in-phone'),
      label: l10n.authPhoneLabel,
      controller: _phone,
      prefixText: KhPhone.countryCode,
      hint: '12 345 678',
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d\s+\-]')),
        LengthLimitingTextInputFormatter(16),
      ],
      helpText: l10n.authPhoneHelp,
      errorText: _phoneError,
      onChanged: (_) {
        if (_phoneError != null) setState(() => _phoneError = null);
      },
      onSubmitted: (_) => _continueWithPhone(),
    ),
    const SizedBox(height: 24),
    KButton(
      label: l10n.uiContinue,
      size: KButtonSize.lg,
      expand: true,
      loading: _busy == _Busy.phone,
      onPressed: _busy == _Busy.none ? _continueWithPhone : null,
    ),
  ];

  List<Widget> _emailForm(AppLocalizations l10n, KTheme k) => [
    KTextField(
      key: const Key('sign-in-email'),
      label: l10n.authEmailLabel,
      controller: _email,
      hint: 'name@example.com',
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.email],
      errorText: _emailError,
      onChanged: (_) {
        if (_emailError != null) setState(() => _emailError = null);
      },
    ),
    const SizedBox(height: 16),
    KTextField(
      key: const Key('sign-in-password'),
      label: l10n.authPasswordLabel,
      controller: _password,
      obscureText: _obscure,
      textInputAction: TextInputAction.done,
      autofillHints: [
        _creatingAccount ? AutofillHints.newPassword : AutofillHints.password,
      ],
      errorText: _passwordError,
      suffix: KIconButton(
        icon: _obscure ? KIcons.eye : KIcons.eyeOff,
        label: _obscure ? l10n.authShowPassword : l10n.authHidePassword,
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
      onChanged: (_) {
        if (_passwordError != null) setState(() => _passwordError = null);
      },
      onSubmitted: (_) => _submitEmail(),
    ),
    if (!_creatingAccount)
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: KButton.ghost(
          label: l10n.authForgotPassword,
          size: KButtonSize.sm,
          onPressed: _forgotPassword,
        ),
      ),
    if (_notice != null) ...[
      const SizedBox(height: 12),
      KBanner(message: _notice!),
    ],
    const SizedBox(height: 16),
    KButton(
      label: _creatingAccount ? l10n.authCreateAccountButton : l10n.authSignIn,
      size: KButtonSize.lg,
      expand: true,
      loading: _busy == _Busy.email,
      onPressed: _busy == _Busy.none ? _submitEmail : null,
    ),
    const SizedBox(height: 16),
    Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          _creatingAccount ? l10n.authHaveAccount : l10n.authNewToK,
          style: k.text.small.copyWith(color: k.colors.muted),
        ),
        KButton.ghost(
          label: _creatingAccount ? l10n.authSignIn : l10n.authCreateAccount,
          size: KButtonSize.sm,
          onPressed: () => setState(() {
            _creatingAccount = !_creatingAccount;
            _passwordError = null;
            _emailError = null;
            _notice = null;
          }),
        ),
      ],
    ),
  ];
}

/// Supabase `[auth] minimum_password_length`.
const minPasswordLength = 6;

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final line = Expanded(child: Divider(color: k.colors.line, height: 1));
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: k.text.small.copyWith(color: k.colors.muted),
          ),
        ),
        line,
      ],
    );
  }
}

/// "By continuing you agree to our Terms and Privacy Policy." The Terms and
/// Privacy pages arrive with the CMS pages (content_pages); until then the
/// names are emphasised but not linked.
class _LegalFooter extends StatelessWidget {
  const _LegalFooter({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final emphasis = TextStyle(
      color: k.colors.ink2,
      fontWeight: FontWeight.w600,
    );
    // Split around placeholder marks so word order follows the translation.
    const termsMark = '{terms}';
    const privacyMark = '{privacy}';
    final text = l10n.authLegal(termsMark, privacyMark);
    final spans = <InlineSpan>[];
    var rest = text;
    while (rest.isNotEmpty) {
      final t = rest.indexOf(termsMark);
      final p = rest.indexOf(privacyMark);
      final next = [t, p]
          .where((i) => i >= 0)
          .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
      if (next == null) {
        spans.add(TextSpan(text: rest));
        break;
      }
      spans.add(TextSpan(text: rest.substring(0, next)));
      final isTerms = next == t;
      spans.add(
        TextSpan(
          text: isTerms ? l10n.authTerms : l10n.authPrivacy,
          style: emphasis,
        ),
      );
      rest = rest.substring(next + (isTerms ? termsMark : privacyMark).length);
    }
    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.center,
      style: k.text.caption.copyWith(
        color: k.colors.muted,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}
