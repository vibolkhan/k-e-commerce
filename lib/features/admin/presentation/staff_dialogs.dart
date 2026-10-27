import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/k_ui.dart';
import '../../auth/domain/phone_number.dart';
import '../data/admin_repository.dart';
import '../domain/staff_member.dart';
import '../domain/staff_outcome.dart';
import '../domain/staff_role.dart';
import 'admin_labels.dart';
import 'admin_providers.dart';

/// A-14e role cards, in the design's order.
const inviteRoleOrder = [
  StaffRole.sales,
  StaffRole.support,
  StaffRole.catalog,
  StaffRole.superAdmin,
];

/// The email or E.164 phone the server will accept, or null.
String? normalizeStaffContact(String input) =>
    input.contains('@') ? normalizeEmail(input) : KhPhone.normalize(input);

/// A-14e. Closes after the invite is sent and refreshes the staff list.
Future<void> showInviteStaffDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: KColors.scrim,
  builder: (_) => const InviteStaffDialog(),
);

/// Edit a member: change their role or remove their staff access.
Future<void> showEditStaffDialog(BuildContext context, StaffMember member) =>
    showDialog<void>(
      context: context,
      barrierColor: KColors.scrim,
      builder: (_) => EditStaffDialog(member: member),
    );

/// Resend on a pending row: a fresh link or SMS, valid 7 more days.
Future<void> resendInvite(
  BuildContext context,
  WidgetRef ref,
  StaffMember member,
) async {
  final l10n = AppLocalizations.of(context);
  final outcome = await ref.read(adminRepositoryProvider).resend(member.id);
  if (!context.mounted) return;
  _toastOutcome(context, l10n, outcome, done: l10n.staffResent);
  if (outcome is StaffDone) ref.invalidate(staffDirectoryProvider);
}

void _toastOutcome(
  BuildContext context,
  AppLocalizations l10n,
  StaffOutcome outcome, {
  required String done,
}) {
  final ok = outcome is StaffDone;
  showKToast(
    context,
    message: switch (outcome) {
      StaffDone() => done,
      StaffRefused(:final reason) => staffRefusalMessage(l10n, reason),
      StaffInvalid() => l10n.staffErrUnknown,
    },
    tone: ok ? KToastTone.ok : KToastTone.bad,
    icon: ok ? KIcons.success : KIcons.error,
  );
}

/// The k-ui `.modal`: title bar, body, right-aligned footer actions.
class _StaffModal extends StatelessWidget {
  const _StaffModal({
    required this.title,
    required this.children,
    required this.actions,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    return Dialog(
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KRadius.dialog),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: k.text.h3.copyWith(
                          fontSize: 18,
                          height: 26 / 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  KIconButton(
                    icon: KIcons.close,
                    label: l10n.uiClose,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, child) in children.indexed) ...[
                      if (i > 0) const SizedBox(height: 16),
                      child,
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line)),
              ),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleOptions extends StatelessWidget {
  const _RoleOptions({required this.selected, required this.onChanged});

  final StaffRole? selected;
  final ValueChanged<StaffRole>? onChanged;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: l10n.staffRoleLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.staffRoleLabel, style: k.text.label),
          const SizedBox(height: 8),
          for (final role in inviteRoleOrder) ...[
            KOptionTile(
              key: Key('role-${role.dbName}'),
              title: staffRoleLabel(l10n, role),
              subtitle: staffRoleDescription(l10n, role),
              selected: role == selected,
              enabled: onChanged != null,
              onTap: () => onChanged?.call(role),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class InviteStaffDialog extends ConsumerStatefulWidget {
  const InviteStaffDialog({super.key});

  @override
  ConsumerState<InviteStaffDialog> createState() => _InviteStaffDialogState();
}

class _InviteStaffDialogState extends ConsumerState<InviteStaffDialog> {
  final _name = TextEditingController();
  final _contact = TextEditingController();
  StaffRole _role = StaffRole.sales;
  StaffField? _invalid;
  StaffRefusal? _refused;
  bool _sending = false;

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    final contact = normalizeStaffContact(_contact.text);
    setState(() {
      _refused = null;
      _invalid = name.isEmpty
          ? StaffField.fullName
          : contact == null
          ? StaffField.contact
          : null;
    });
    if (_invalid != null) return;

    setState(() => _sending = true);
    final outcome = await ref
        .read(adminRepositoryProvider)
        .invite(fullName: name, contact: contact!, role: _role);
    if (!mounted) return;
    setState(() => _sending = false);
    switch (outcome) {
      case StaffDone():
        ref.invalidate(staffDirectoryProvider);
        Navigator.of(context).pop();
        _toastOutcome(
          context,
          l10n,
          outcome,
          done: l10n.staffInvited(_contact.text.trim()),
        );
      case StaffInvalid(:final field):
        setState(() => _invalid = field);
      case StaffRefused(:final reason):
        setState(() => _refused = reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _StaffModal(
      title: l10n.staffInviteTitle,
      actions: [
        KButton.outline(
          label: l10n.uiCancel,
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
        ),
        KButton(
          key: const Key('send-invite'),
          label: l10n.staffSendInvite,
          loading: _sending,
          loadingLabel: l10n.staffSendInvite,
          onPressed: _send,
        ),
      ],
      children: [
        if (_refused != null)
          KBanner(
            key: const Key('invite-error'),
            message: staffRefusalMessage(l10n, _refused!),
            tone: KBannerTone.bad,
          ),
        KTextField(
          key: const Key('invite-name'),
          label: l10n.staffFullName,
          controller: _name,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          errorText: _invalid == StaffField.fullName
              ? l10n.staffNameRequired
              : null,
        ),
        KTextField(
          key: const Key('invite-contact'),
          label: l10n.staffContact,
          controller: _contact,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          helpText: l10n.staffContactHelp,
          errorText: _invalid == StaffField.contact
              ? l10n.staffContactInvalid
              : null,
          onSubmitted: (_) => _send(),
        ),
        _RoleOptions(
          selected: _role,
          onChanged: _sending ? null : (role) => setState(() => _role = role),
        ),
      ],
    );
  }
}

class EditStaffDialog extends ConsumerStatefulWidget {
  const EditStaffDialog({super.key, required this.member});

  final StaffMember member;

  @override
  ConsumerState<EditStaffDialog> createState() => _EditStaffDialogState();
}

class _EditStaffDialogState extends ConsumerState<EditStaffDialog> {
  late StaffRole _role = widget.member.role;
  StaffRefusal? _refused;
  bool _busy = false;

  String get _name => widget.member.fullName ?? widget.member.contact;

  Future<void> _run(Future<StaffOutcome> Function() call, String done) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _refused = null;
    });
    final outcome = await call();
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case StaffDone():
        ref.invalidate(staffDirectoryProvider);
        Navigator.of(context).pop();
        _toastOutcome(context, l10n, outcome, done: done);
      case StaffRefused(:final reason):
        setState(() => _refused = reason);
      case StaffInvalid():
        setState(() => _refused = StaffRefusal.unknown);
    }
  }

  Future<void> _saveRole() async {
    final l10n = AppLocalizations.of(context);
    final roleName = staffRoleLabel(l10n, _role);
    final ok = await showKConfirm(
      context,
      title: l10n.staffRoleConfirmTitle,
      message: l10n.staffRoleConfirmBody(_name, roleName),
      confirmLabel: l10n.staffRoleConfirm,
      cancelLabel: l10n.uiCancel,
      icon: KIcons.lock,
    );
    if (!ok || !mounted) return;
    await _run(
      () =>
          ref.read(adminRepositoryProvider).updateRole(widget.member.id, _role),
      l10n.staffUpdated,
    );
  }

  Future<void> _remove() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showKConfirm(
      context,
      title: l10n.staffRemoveConfirmTitle(_name),
      message: l10n.staffRemoveConfirmBody,
      confirmLabel: l10n.staffRemoveConfirm,
      cancelLabel: l10n.uiCancel,
      tone: KConfirmTone.destructive,
      icon: KIcons.delete,
    );
    if (!ok || !mounted) return;
    await _run(
      () => ref.read(adminRepositoryProvider).remove(widget.member.id),
      l10n.staffRemoved(_name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final changed = _role != widget.member.role;
    return _StaffModal(
      title: l10n.staffEditTitle(_name),
      actions: [
        KButton(
          key: const Key('remove-staff'),
          label: l10n.staffRemove,
          variant: KButtonVariant.dangerOutline,
          onPressed: _busy ? null : _remove,
        ),
        KButton.outline(
          label: l10n.uiCancel,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        KButton(
          key: const Key('save-role'),
          label: l10n.staffSaveRole,
          loading: _busy,
          loadingLabel: l10n.staffSaveRole,
          onPressed: changed && !_busy ? _saveRole : null,
        ),
      ],
      children: [
        if (_refused != null)
          KBanner(
            key: const Key('edit-error'),
            message: staffRefusalMessage(l10n, _refused!),
            tone: KBannerTone.bad,
          ),
        _RoleOptions(
          selected: _role,
          onChanged: _busy ? null : (role) => setState(() => _role = role),
        ),
      ],
    );
  }
}
