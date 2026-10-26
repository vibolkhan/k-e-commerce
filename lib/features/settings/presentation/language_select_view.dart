import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_controller.dart';
import '../../../core/ui/k_ui.dart';
import 'language_options.dart';

/// First-launch language choice (S-02). Picking a card switches the app
/// language at once so the screen itself previews it; Continue hands over to
/// the next onboarding step. F06 mounts this on the launch route.
class LanguageSelectView extends ConsumerWidget {
  const LanguageSelectView({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
              children: [
                const Align(alignment: Alignment.centerLeft, child: KLogo()),
                const SizedBox(height: KSpacing.x8),
                Semantics(
                  header: true,
                  child: Text(
                    l10n.languageChooseTitle,
                    style: k.text.h1.copyWith(fontSize: 28, height: 36 / 28),
                  ),
                ),
                const SizedBox(height: KSpacing.x2),
                Text(
                  l10n.languageChooseSubtitle,
                  style: k.text.body.copyWith(color: k.colors.muted),
                ),
                const SizedBox(height: KSpacing.x8),
                LanguageOptions(
                  style: LanguageOptionsStyle.cards,
                  selected: Localizations.localeOf(context),
                  onChanged: ref
                      .read(localeControllerProvider.notifier)
                      .setLocale,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
            child: KButton(
              label: l10n.uiContinue,
              size: KButtonSize.lg,
              expand: true,
              onPressed: onContinue,
            ),
          ),
        ],
      ),
    );
  }
}
