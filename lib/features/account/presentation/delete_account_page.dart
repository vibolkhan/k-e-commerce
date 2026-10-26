import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/ui/k_ui.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/account_repository.dart';
import '../domain/delete_account_outcome.dart';
import '../domain/delete_reason.dart';

/// S-08f → S-08g (AUTH-07). What goes and what stays, an optional reason,
/// and an "I understand" tick before the danger button is enabled. The
/// server decides whether the account can go (no open orders or returns).
class DeleteAccountPage extends ConsumerStatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  ConsumerState<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends ConsumerState<DeleteAccountPage> {
  DeleteReason? _reason;
  var _understood = false;
  var _busy = false;

  /// Why the server refused, shown above the form.
  String? _refusal;
  final _reasonText = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _showReason();
  }

  @override
  void dispose() {
    _reasonText.dispose();
    super.dispose();
  }

  /// The picked reason in the current language.
  void _showReason() {
    final reason = _reason;
    _reasonText.text = reason == null
        ? ''
        : _reasonLabel(AppLocalizations.of(context), reason);
  }

  String _reasonLabel(AppLocalizations l10n, DeleteReason reason) =>
      switch (reason) {
        DeleteReason.notUsing => l10n.deleteReasonNotUsing,
        DeleteReason.otherAccount => l10n.deleteReasonOtherAccount,
        DeleteReason.privacy => l10n.deleteReasonPrivacy,
        DeleteReason.notifications => l10n.deleteReasonNotifications,
        DeleteReason.other => l10n.deleteReasonOther,
      };

  Future<void> _pickReason() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showKBottomSheet<DeleteReason>(
      context,
      title: l10n.deleteReasonLabel,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final reason in DeleteReason.values)
            Padding(
              padding: const EdgeInsets.only(bottom: KSpacing.x2),
              child: KOptionTile(
                title: _reasonLabel(l10n, reason),
                selected: reason == _reason,
                onTap: () => Navigator.of(sheet).pop(reason),
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() => _reason = picked);
    _showReason();
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showKConfirm(
      context,
      title: l10n.deleteConfirmTitle,
      message: l10n.deleteConfirmBody,
      cancelLabel: l10n.deleteKeep,
      confirmLabel: l10n.deleteConfirm,
      tone: KConfirmTone.destructive,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _refusal = null;
    });
    final outcome = await ref
        .read(accountRepositoryProvider)
        .deleteAccount(reason: _reason?.code);
    if (outcome is AccountDeleted) {
      // Every session is already revoked on the server; drop this one.
      await ref.read(authRepositoryProvider).signOut();
      if (!mounted) return;
      showKToast(context, message: l10n.deleteDone);
      context.go(AppRoutes.customer);
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _refusal = switch (outcome) {
        HasActiveOrders() => l10n.deleteActiveBody,
        DeleteNotAllowed() => l10n.deleteNotAllowed,
        _ => null,
      };
    });
    if (outcome is DeleteFailed) {
      showKToast(context, message: l10n.authNetworkError, tone: KToastTone.bad);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    return Stack(
      children: [
        Scaffold(
          backgroundColor: c.surface,
          appBar: KAppBar(title: l10n.accountDelete, line: true),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            children: [
              if (_refusal != null) ...[
                KBanner(
                  key: const Key('delete-refusal'),
                  tone: KBannerTone.warn,
                  message: _refusal!,
                ),
                const SizedBox(height: 18),
              ],
              KBanner.rich(
                tone: KBannerTone.bad,
                span: TextSpan(
                  children: [
                    TextSpan(
                      text: l10n.deleteWarningBold,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: ' ${l10n.deleteWarning}'),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _Heading(l10n.deleteWhatGoes),
              const SizedBox(height: 10),
              for (final item in [
                l10n.deleteGoesProfile,
                l10n.deleteGoesWishlist,
                l10n.deleteGoesChat,
              ])
                _Point(icon: KIcons.close, color: c.bad, text: item),
              const SizedBox(height: 8),
              _Heading(l10n.deleteWhatStays),
              const SizedBox(height: 10),
              _Point(
                icon: KIcons.invoice,
                color: c.primaryInk,
                text: l10n.deleteStaysInvoices,
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: c.line),
              const SizedBox(height: 18),
              KTextField(
                key: const Key('delete-reason'),
                controller: _reasonText,
                label: l10n.deleteReasonLabel,
                optional: true,
                hint: l10n.deleteReasonHint,
                readOnly: true,
                suffix: KIcon(KIcons.chevronDown, size: 20, color: c.muted),
                onTap: _pickReason,
              ),
              const SizedBox(height: 12),
              MergeSemantics(
                child: InkWell(
                  key: const Key('delete-understand'),
                  borderRadius: BorderRadius.circular(KRadius.input),
                  onTap: () => setState(() => _understood = !_understood),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: kMinTap),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _understood,
                          onChanged: (v) => setState(() => _understood = v!),
                        ),
                        Expanded(
                          child: Text(
                            l10n.deleteUnderstand,
                            style: k.text.small.copyWith(
                              fontSize: 14,
                              height: 20 / 14,
                              color: c.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: KButton(
                key: const Key('delete-submit'),
                label: l10n.accountDelete,
                variant: KButtonVariant.danger,
                size: KButtonSize.lg,
                expand: true,
                onPressed: _understood && !_busy ? _delete : null,
              ),
            ),
          ),
        ),
        if (_busy)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.white.withValues(alpha: .7),
              child: Center(
                child: KBlockingProgress(message: l10n.deleteProgress),
              ),
            ),
          ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Semantics(header: true, child: Text(text, style: context.k.text.h3));
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.color, required this.text});

  final KIconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KIcon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: k.text.small.copyWith(color: k.colors.ink2),
            ),
          ),
        ],
      ),
    );
  }
}
