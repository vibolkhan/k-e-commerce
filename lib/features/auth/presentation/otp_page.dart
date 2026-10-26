import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/time/date_format.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/auth_outcome.dart';
import '../domain/phone_number.dart';
import 'auth_dialogs.dart';
import 'auth_flow.dart';
import 'auth_providers.dart';

/// S-05 / S-05b / S-05c: enter the 6-digit code. Wrong codes count down on
/// the server; the 5th locks the number for 15 minutes. Pops an
/// [AuthStepResult].
class OtpPage extends ConsumerStatefulWidget {
  const OtpPage({
    super.key,
    required this.phone,
    this.resendIn = const Duration(seconds: 60),
  });

  /// E.164 (`+85512345678`).
  final String phone;

  /// Time until "Resend code" unlocks.
  final Duration resendIn;

  @override
  ConsumerState<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends ConsumerState<OtpPage> {
  final _code = TextEditingController();
  Timer? _timer;
  late int _resendIn = widget.resendIn.inSeconds;
  int? _triesLeft;
  DateTime? _lockedUntil;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
    _startCountdown(_resendIn);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _resendIn = seconds);
    if (seconds <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _resendIn--);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  bool get _locked => _lockedUntil != null;

  Future<void> _verify() async {
    if (_busy || _code.text.length != 6 || _locked) return;
    setState(() => _busy = true);
    final outcome = await ref
        .read(authRepositoryProvider)
        .verifyOtp(widget.phone, _code.text);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case SignedIn(:final isNewUser):
        if (await completeSignIn(context, isNewUser: isNewUser) && mounted) {
          context.pop(AuthStepResult.done);
        }
      case WrongCredentials(:final triesLeft):
        setState(() => _triesLeft = triesLeft);
      case Locked():
        await _onLocked(outcome);
      case Blocked():
        await showBlockedDialog(context, ref);
        if (mounted) context.pop();
      default:
        _failed();
    }
  }

  Future<void> _resend() async {
    if (_busy || _locked) return;
    setState(() => _busy = true);
    final outcome = await ref
        .read(authRepositoryProvider)
        .sendOtp(widget.phone);
    if (!mounted) return;
    setState(() => _busy = false);
    final l10n = AppLocalizations.of(context);
    switch (outcome) {
      case OtpSent(:final resendIn):
        _code.clear();
        setState(() => _triesLeft = null);
        _startCountdown(resendIn.inSeconds);
        showKToast(context, message: l10n.authOtpResent);
      case ResendTooSoon(:final resendIn):
        _startCountdown(resendIn.inSeconds);
      case Locked():
        await _onLocked(outcome);
      case Blocked():
        await showBlockedDialog(context, ref);
        if (mounted) context.pop();
      case SendFailed():
        showKToast(context, message: l10n.authSendFailed, tone: KToastTone.bad);
      default:
        _failed();
    }
  }

  Future<void> _onLocked(Locked locked) async {
    setState(() {
      _lockedUntil = locked.until;
      _triesLeft = 0;
    });
    _timer?.cancel();
    final useEmail = await showLockedDialog(
      context,
      ref,
      locked,
      viaPhone: true,
    );
    if (useEmail && mounted) context.pop(AuthStepResult.useEmail);
  }

  void _failed() => showKToast(
    context,
    message: AppLocalizations.of(context).authNetworkError,
    tone: KToastTone.bad,
  );

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final error = _triesLeft != null;
    final canVerify = _code.text.length == 6 && !_busy && !_locked;
    final countdown =
        '${_resendIn ~/ 60}:${(_resendIn % 60).toString().padLeft(2, '0')}';
    final (sentBefore, sentAfter) = splitAroundPlaceholder(l10n.authOtpSentTo);
    final (resendBefore, resendAfter) = splitAroundPlaceholder(
      l10n.authOtpResendIn,
    );

    return Scaffold(
      backgroundColor: c.surface,
      appBar: const AuthTopBar(),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Semantics(
              header: true,
              child: Text(l10n.authOtpTitle, style: k.text.h1),
            ),
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: sentBefore),
                      TextSpan(
                        text: KhPhone.display(widget.phone),
                        style: TextStyle(
                          color: c.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(text: '$sentAfter · '),
                    ],
                  ),
                  style: k.text.body.copyWith(color: c.muted),
                ),
                KButton.ghost(
                  label: l10n.authOtpChange,
                  size: KButtonSize.sm,
                  onPressed: () => context.pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            KOtpField(
              key: const Key('otp-code'),
              controller: _code,
              error: error,
              enabled: !_locked,
              autofocus: true,
              onChanged: (_) {
                if (_triesLeft != null && !_locked) {
                  setState(() => _triesLeft = null);
                }
              },
            ),
            const SizedBox(height: 12),
            if (_locked)
              AuthErrorText(
                l10n.authLockedInline(formatTime(l10n, _lockedUntil!)),
              )
            else if (error)
              AuthErrorText(l10n.authOtpWrong(_triesLeft!)),
            const SizedBox(height: 16),
            if (!_locked)
              if (_resendIn > 0)
                Row(
                  children: [
                    KIcon(KIcons.time, size: 18, color: c.ink2),
                    const SizedBox(width: 8),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: resendBefore),
                          TextSpan(
                            text: countdown,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          TextSpan(text: resendAfter),
                        ],
                      ),
                      style: k.text.small.copyWith(color: c.ink2),
                    ),
                  ],
                )
              else
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l10n.authOtpDidntGet,
                      style: k.text.small.copyWith(color: c.ink2),
                    ),
                    KButton.ghost(
                      label: l10n.authOtpResend,
                      size: KButtonSize.sm,
                      onPressed: _busy ? null : _resend,
                    ),
                  ],
                ),
            const SizedBox(height: 8),
            Text(
              l10n.authOtpExpiry(otpExpiryMinutes),
              style: k.text.caption.copyWith(
                color: c.muted,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: KButton(
            key: const Key('otp-verify'),
            label: l10n.authOtpVerify,
            size: KButtonSize.lg,
            expand: true,
            loading: _busy,
            onPressed: canVerify ? _verify : null,
          ),
        ),
      ),
    );
  }
}
