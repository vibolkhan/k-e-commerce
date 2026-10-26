import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/ui/k_ui.dart';

/// How a pushed sign-in step (S-05, S-06) ended. Each page pops with this so
/// the flow unwinds back to S-04, and S-04 pops `true` to whoever asked for
/// sign-in — the page underneath was never removed, so its state is intact.
enum AuthStepResult {
  /// Signed in (and profile complete).
  done,

  /// S-05c "Use email": back to S-04 on the email tab.
  useEmail,
}

/// Codes expire after this long (Supabase `[auth.sms] otp_expiry`, App Flow F1).
const otpExpiryMinutes = 5;

/// [from] as an in-app path, or null. Only same-app absolute paths are
/// accepted so a crafted link can't send people elsewhere after sign-in.
String? safeReturnPath(String? from) {
  if (from == null || !from.startsWith('/') || from.startsWith('//')) {
    return null;
  }
  if (AppRoutes.isSignInFlow(Uri.parse(from).path)) return null;
  return from;
}

/// The text before and after a message's single placeholder, so the value
/// can be styled (bold phone, countdown) while word order follows the
/// translation.
(String, String) splitAroundPlaceholder(String Function(String) message) {
  const mark = '\u0000';
  final parts = message(mark).split(mark);
  return (parts.first, parts.length > 1 ? parts.last : '');
}

/// After a successful sign-in: S-06 for new users, then report whether the
/// flow is complete.
Future<bool> completeSignIn(
  BuildContext context, {
  required bool isNewUser,
}) async {
  if (!isNewUser) return true;
  final result = await context.push<AuthStepResult>(AppRoutes.signInProfile);
  return result == AuthStepResult.done;
}

/// The sign-in screens' top bar: close (S-04) or back (S-05), no title.
class AuthTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AuthTopBar({super.key, this.close = false, this.onPressed});

  final bool close;
  final VoidCallback? onPressed;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: context.k.colors.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          child: KIconButton(
            icon: close ? KIcons.close : KIcons.back,
            label: close ? l10n.uiClose : l10n.uiBack,
            onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
    );
  }
}

/// Red inline message with the alert icon, as under the S-05b code boxes.
class AuthErrorText extends StatelessWidget {
  const AuthErrorText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KIcon(KIcons.alert, size: 16, color: k.colors.bad),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: k.text.caption.copyWith(
                color: k.colors.bad,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
