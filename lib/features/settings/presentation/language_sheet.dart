import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_controller.dart';
import '../../../core/ui/k_ui.dart';
import 'language_options.dart';

/// Account › Language (S-08c). Saving switches the whole app immediately.
Future<void> showLanguageSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showKBottomSheet<void>(
    context,
    title: l10n.languageTitle,
    builder: (_) => const LanguageSheetBody(),
  );
}

class LanguageSheetBody extends ConsumerStatefulWidget {
  const LanguageSheetBody({super.key});

  @override
  ConsumerState<LanguageSheetBody> createState() => _LanguageSheetBodyState();
}

class _LanguageSheetBodyState extends ConsumerState<LanguageSheetBody> {
  Locale? _picked;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final current = Localizations.localeOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LanguageOptions(
          selected: _picked ?? current,
          current: current,
          onChanged: (locale) => setState(() => _picked = locale),
        ),
        const SizedBox(height: KSpacing.x3),
        Text(
          l10n.languageHint,
          style: k.text.small.copyWith(color: k.colors.muted),
        ),
        const SizedBox(height: KSpacing.x4),
        KButton(
          label: l10n.languageSave,
          size: KButtonSize.lg,
          expand: true,
          onPressed: () {
            final picked = _picked;
            Navigator.of(context).pop();
            if (picked != null) {
              ref.read(localeControllerProvider.notifier).setLocale(picked);
            }
          },
        ),
      ],
    );
  }
}
