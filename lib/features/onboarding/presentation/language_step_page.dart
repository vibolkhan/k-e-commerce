import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/locale_controller.dart';
import '../../settings/presentation/language_select_view.dart';
import '../data/onboarding_store.dart';

/// S-02 on first launch. Continue saves the language on screen — even if
/// the person kept the preselected one — and the router moves on to S-03.
class LanguageStepPage extends ConsumerWidget {
  const LanguageStepPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: LanguageSelectView(
        onContinue: () async {
          await ref
              .read(localeControllerProvider.notifier)
              .setLocale(Localizations.localeOf(context));
          await ref
              .read(onboardingProgressProvider.notifier)
              .complete(OnboardingStep.language);
        },
      ),
    );
  }
}
