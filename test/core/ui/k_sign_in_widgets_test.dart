import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/core/ui/k_ui.dart';

import '../../helpers.dart';

void main() {
  testWidgets('social button: one labelled button, 48 px, taps once', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      kHarness(
        KSocialButton(
          provider: KSocialProvider.google,
          label: 'Continue with Google',
          onPressed: () => taps++,
        ),
      ),
    );
    expect(tester.getSize(find.byType(KSocialButton)).height, 48);
    expect(find.byType(KSocialLogo), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(KSocialButton)),
      matchesSemantics(
        label: 'Continue with Google',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.byType(KSocialButton));
    expect(taps, 1);
  });

  testWidgets('social button: loading shows a spinner and ignores taps', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      kHarness(
        KSocialButton(
          provider: KSocialProvider.apple,
          label: 'Continue with Apple',
          loading: true,
          onPressed: () => taps++,
        ),
      ),
    );
    expect(find.byType(KSpinner), findsOneWidget);
    await tester.tap(find.byType(KSocialButton));
    expect(taps, 0);
  });

  testWidgets('confirm dialog icon tone colours only the icon', (tester) async {
    await tester.pumpWidget(
      kHarness(
        const KConfirmDialog(
          title: 'Too many attempts',
          message: 'Wait 15 minutes.',
          confirmLabel: 'OK',
          cancelLabel: 'Use email',
          icon: KIcons.lock,
          iconTone: KBannerTone.warn,
        ),
      ),
    );
    final icon = tester.widget<KIcon>(
      find.descendant(
        of: find.byType(KConfirmDialog),
        matching: find.byType(KIcon),
      ),
    );
    expect(icon.icon, KIcons.lock);
    expect(icon.color, KColors.warnText);
    // The confirm button stays primary, not destructive.
    expect(
      tester.widget<KButton>(find.widgetWithText(KButton, 'OK')).variant,
      KButtonVariant.primary,
    );
  });
}
