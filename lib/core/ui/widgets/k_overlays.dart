import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../l10n/generated/app_localizations.dart';
import '../icons/k_icon.dart';
import '../icons/k_icons.dart';
import '../theme/k_theme.dart';
import '../theme/k_tokens.dart';
import 'k_button.dart';

// ---------------------------------------------------------------- toast

enum KToastTone { ok, info, bad }

/// Dark toast for quick results, with an optional action ("Undo").
class KToast extends StatelessWidget {
  const KToast({
    super.key,
    required this.message,
    this.tone = KToastTone.ok,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final KToastTone tone;
  final KIconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final (accent, defaultIcon) = switch (tone) {
      KToastTone.ok => (KColors.toastOk, KIcons.success),
      KToastTone.info => (KColors.sky300, KIcons.info),
      KToastTone.bad => (KColors.toastBad, KIcons.error),
    };
    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        color: k.colors.ink,
        borderRadius: BorderRadius.circular(KRadius.box),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KRadius.box),
            boxShadow: k.shadow3,
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            actionLabel == null ? 16 : 10,
            10,
          ),
          child: Row(
            children: [
              KIcon(icon ?? defaultIcon, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: k.text.small.copyWith(
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              if (actionLabel != null) ...[
                const SizedBox(width: 12),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: KColors.sky300,
                    minimumSize: const Size(kMinTap, kMinTap),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(KRadius.buttonSm),
                    ),
                    textStyle: k.text.button.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

OverlayEntry? _currentToast;
Timer? _toastTimer;

/// Shows a [KToast] near the bottom (above the bottom nav) for [duration].
/// A new toast replaces the current one.
void showKToast(
  BuildContext context, {
  required String message,
  KToastTone tone = KToastTone.ok,
  KIconData? icon,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
  double bottom = 104,
}) {
  hideKToast();
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => Positioned(
      left: 16,
      right: 16,
      bottom: bottom + MediaQuery.viewPaddingOf(context).bottom,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: KToast(
              message: message,
              tone: tone,
              icon: icon,
              actionLabel: actionLabel,
              onAction: onAction == null
                  ? null
                  : () {
                      hideKToast();
                      onAction();
                    },
            ),
          ),
        ),
      ),
    ),
  );
  _currentToast = entry;
  overlay.insert(entry);
  SemanticsService.sendAnnouncement(
    View.of(context),
    message,
    Directionality.of(context),
  );
  _toastTimer = Timer(duration, hideKToast);
}

void hideKToast() {
  _toastTimer?.cancel();
  _toastTimer = null;
  _currentToast?.remove();
  _currentToast = null;
}

// ---------------------------------------------------------------- sheet

/// Bottom sheet body: grab handle, title, close button, content.
class KBottomSheet extends StatelessWidget {
  const KBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.onClose,
    this.showClose = true,
  });

  final String? title;
  final Widget child;

  /// Defaults to popping the route.
  final VoidCallback? onClose;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(KRadius.sheet),
        ),
        boxShadow: k.shadow3,
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        32 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: c.line2,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (title != null || showClose) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: title == null
                      ? const SizedBox()
                      : Semantics(
                          header: true,
                          child: Text(title!, style: k.text.title),
                        ),
                ),
                if (showClose)
                  KIconButton(
                    icon: KIcons.close,
                    label: l10n.uiClose,
                    style: KIconButtonStyle.soft,
                    onPressed: onClose ?? () => Navigator.of(context).pop(),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// Opens a [KBottomSheet] as a modal. Returns what the sheet pops with.
Future<T?> showKBottomSheet<T>(
  BuildContext context, {
  String? title,
  required WidgetBuilder builder,
  bool showClose = true,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: KColors.scrim,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: KBottomSheet(
        title: title,
        showClose: showClose,
        child: builder(context),
      ),
    ),
  );
}

// ---------------------------------------------------------------- dialog

enum KConfirmTone {
  /// Sky icon, primary confirm button.
  neutral,

  /// Red icon and red confirm button.
  destructive,
}

/// Confirmation before anything that costs money, removes data or cancels
/// work: icon, short title, one-sentence consequence, two actions. The
/// confirm label names what happens — never just "OK".
///
/// For neutral prompts word it so the confirm (primary) button is the safe
/// choice, e.g. "Leave payment?" → cancel "Leave", confirm "Stay and pay".
class KConfirmDialog extends StatelessWidget {
  const KConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    this.tone = KConfirmTone.neutral,
    this.icon,
    this.alternativeLabel,
    this.onConfirm,
    this.onCancel,
    this.onAlternative,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final KConfirmTone tone;

  /// Defaults to info (neutral) or delete (destructive).
  final KIconData? icon;

  /// Optional ghost action under the buttons ("Move to wishlist instead").
  final String? alternativeLabel;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final VoidCallback? onAlternative;

  bool get _destructive => tone == KConfirmTone.destructive;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final (iconBg, iconFg) = _destructive
        ? (c.badBg, c.bad)
        : (c.tint2, c.primaryInk);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(KRadius.dialog),
          boxShadow: k.shadow3,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: KIcon(
                  icon ?? (_destructive ? KIcons.delete : KIcons.info),
                  size: 28,
                  color: iconFg,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Semantics(header: true, child: Text(title, style: k.text.title)),
            const SizedBox(height: 16),
            Text(
              message,
              style: k.text.small.copyWith(
                fontSize: 14,
                height: 21 / 14,
                color: c.ink2,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: KButton.outline(
                    label: cancelLabel,
                    expand: true,
                    onPressed: onCancel,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: KButton(
                    label: confirmLabel,
                    expand: true,
                    variant: _destructive
                        ? KButtonVariant.danger
                        : KButtonVariant.primary,
                    onPressed: onConfirm,
                  ),
                ),
              ],
            ),
            if (alternativeLabel != null) ...[
              const SizedBox(height: 16),
              Center(
                child: KButton.ghost(
                  label: alternativeLabel!,
                  size: KButtonSize.sm,
                  onPressed: onAlternative,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows a [KConfirmDialog]. Resolves true on confirm; false on cancel,
/// on the alternative action, or when dismissed.
Future<bool> showKConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  KConfirmTone tone = KConfirmTone.neutral,
  KIconData? icon,
  String? alternativeLabel,
  VoidCallback? onAlternative,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: KColors.scrim,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: KConfirmDialog(
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          tone: tone,
          icon: icon,
          alternativeLabel: alternativeLabel,
          onConfirm: () => Navigator.of(context).pop(true),
          onCancel: () => Navigator.of(context).pop(false),
          onAlternative: () {
            Navigator.of(context).pop(false);
            onAlternative?.call();
          },
        ),
      ),
    ),
  );
  return result ?? false;
}

// ---------------------------------------------------------------- blocking

/// Card with spinner over a white scrim while something must finish
/// ("Confirming your payment…").
class KBlockingProgress extends StatelessWidget {
  const KBlockingProgress({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Semantics(
      liveRegion: true,
      label: message,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        decoration: BoxDecoration(
          color: k.colors.surface,
          borderRadius: BorderRadius.circular(KRadius.card),
          boxShadow: k.shadow2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: k.colors.primary,
                backgroundColor: KColors.sky200,
              ),
            ),
            const SizedBox(width: 14),
            ExcludeSemantics(
              child: Text(
                message,
                style: k.text.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
