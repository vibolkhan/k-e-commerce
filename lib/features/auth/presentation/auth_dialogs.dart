import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/time/phnom_penh_time.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/auth_outcome.dart';
import 'auth_providers.dart';

/// Minutes left on a lock, rounded up (the server sets 15).
int lockMinutesLeft(WidgetRef ref, Locked locked) {
  final left = locked.until.difference(ref.read(clockProvider)());
  return (left.inSeconds / 60).ceil().clamp(1, 24 * 60);
}

/// S-05c "Too many attempts". From a phone lock it offers email instead;
/// from an email lock it offers phone. Resolves true when the person picked
/// the other method.
Future<bool> showLockedDialog(
  BuildContext context,
  WidgetRef ref,
  Locked locked, {
  required bool viaPhone,
}) async {
  final l10n = AppLocalizations.of(context);
  final minutes = lockMinutesLeft(ref, locked);
  final ok = await showKConfirm(
    context,
    title: l10n.authLockedTitle,
    message: viaPhone
        ? l10n.authLockedBodyPhone(minutes)
        : l10n.authLockedBodyEmail(minutes),
    cancelLabel: viaPhone ? l10n.authLockedUseEmail : l10n.authLockedUsePhone,
    confirmLabel: l10n.authOk,
    icon: KIcons.lock,
    iconTone: KBannerTone.warn,
    barrierDismissible: false,
  );
  return !ok;
}

/// S-06b "This account is unavailable". The person cannot continue; the
/// session (if any) has already been dropped.
Future<void> showBlockedDialog(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final contact = await showKConfirm(
    context,
    title: l10n.authBlockedTitle,
    message: l10n.authBlockedBody,
    cancelLabel: l10n.uiClose,
    confirmLabel: l10n.authContactSupport,
    icon: KIcons.blocked,
    iconTone: KBannerTone.bad,
  );
  if (!contact || !context.mounted) return;
  final open = ref.read(contactSupportProvider);
  if (open != null) {
    open();
  } else {
    showKToast(context, message: l10n.authSupportComingSoon);
  }
}
