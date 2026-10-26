import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/k_ui.dart';
import '../../auth/domain/phone_number.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/account_repository.dart';
import 'account_actions.dart';

/// S-08b: name and contact email. The phone is the sign-in number and is
/// shown read-only; changing it (and the photo) comes in a later task.
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  var _busy = false;
  String? _nameError;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(currentProfileProvider).value;
    _name = TextEditingController(text: profile?.fullName ?? '');
    _email = TextEditingController(text: profile?.email ?? '');
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
          .read(accountRepositoryProvider)
          .updateProfile(fullName: name, email: email);
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
    showKToast(context, message: l10n.editProfileSaved);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final phone = ref.watch(currentProfileProvider).value?.phone;
    return Scaffold(
      backgroundColor: c.surface,
      appBar: KAppBar(title: l10n.editProfileTitle, line: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        children: [
          Center(
            child: ListenableBuilder(
              listenable: _name,
              builder: (_, _) => SizedBox.square(
                dimension: 96,
                child: FittedBox(
                  child: KAvatar(initialsOf(_name.text), size: KAvatarSize.lg),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          KTextField(
            key: const Key('edit-name'),
            label: l10n.authFullName,
            controller: _name,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            errorText: _nameError,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          if (phone != null) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: Text(l10n.authPhoneLabel, style: k.text.label)),
                KStatusPill(label: l10n.editProfileVerified, tone: KTone.green),
              ],
            ),
            const SizedBox(height: 6),
            KTextField(
              key: const Key('edit-phone'),
              initialValue: KhPhone.display(phone),
              enabled: false,
              helpText: l10n.editProfilePhoneHelp,
            ),
          ],
          const SizedBox(height: 20),
          KTextField(
            key: const Key('edit-email'),
            label: l10n.authEmailLabel,
            optional: true,
            controller: _email,
            hint: 'name@example.com',
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            errorText: _emailError,
            onChanged: (_) {
              if (_emailError != null) setState(() => _emailError = null);
            },
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: KButton(
            key: const Key('edit-save'),
            label: l10n.editProfileSave,
            size: KButtonSize.lg,
            expand: true,
            loading: _busy,
            onPressed: _busy ? null : _save,
          ),
        ),
      ),
    );
  }
}
