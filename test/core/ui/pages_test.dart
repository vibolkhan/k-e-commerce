import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/core/ui/pages/error_page.dart';
import 'package:k_e_commerce/core/ui/pages/loading_page.dart';

import '../../helpers.dart';

void main() {
  testWidgets('LoadingPage shows a spinner and label', (tester) async {
    await tester.pumpWidget(localized(const LoadingPage()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading…'), findsOneWidget);
  });

  testWidgets('ErrorPage variants show their copy', (tester) async {
    const cases = [
      (ErrorPage.notFound(), 'Page not found'),
      (ErrorPage.forbidden(), 'No access'),
      (ErrorPage(), 'Something went wrong'),
    ];
    for (final (page, title) in cases) {
      await tester.pumpWidget(localized(page));
      expect(find.text(title), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Go home'), findsOneWidget);
    }
  });

  testWidgets('pages render in Khmer', (tester) async {
    await tester.pumpWidget(
      localized(const ErrorPage.notFound(), locale: const Locale('km')),
    );
    await tester.pumpAndSettle();
    expect(find.text('រកមិនឃើញទំព័រ'), findsOneWidget);
    expect(find.text('ទៅទំព័រដើម'), findsOneWidget);
  });
}
