import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/k_ui.dart';
import '../../auth/presentation/auth_providers.dart';

/// S-08e. Signs out after confirmation; the router then moves a rider or
/// staff member to the guest Customer Home.
Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showKConfirm(
    context,
    title: l10n.signOutTitle,
    message: l10n.signOutBody,
    cancelLabel: l10n.uiCancel,
    confirmLabel: l10n.authSignOut,
    icon: KIcons.account,
  );
  if (!ok) return;
  await ref.read(authRepositoryProvider).signOut();
}

/// Rows whose screens arrive with later tasks (orders, wishlist, help…).
void showComingSoon(BuildContext context) {
  showKToast(
    context,
    message: AppLocalizations.of(context).accountComingSoon,
    tone: KToastTone.info,
    icon: KIcons.info,
  );
}

/// Up to two initials for the avatar ("Dara Sok" → "DS").
String initialsOf(String? name) {
  final words = (name ?? '').trim().split(RegExp(r'\s+'));
  final letters = [
    for (final word in words.take(2))
      if (word.isNotEmpty) String.fromCharCode(word.runes.first),
  ];
  return letters.isEmpty ? '?' : letters.join().toUpperCase();
}
