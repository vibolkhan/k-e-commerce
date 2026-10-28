import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/app.dart';

import 'helpers.dart';

void main() {
  testWidgets('app shell starts and flags missing Supabase config', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(overrides: [onboardedDevice], child: const KApp()),
    );
    await tester.pumpAndSettle();
    expect(storeHome('customer'), findsOneWidget);
    expect(
      find.text('Supabase not configured — running offline'),
      findsOneWidget,
    );
  });

  testWidgets('app shell renders in Khmer', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [onboardedDevice],
        child: const KApp(locale: Locale('km')),
      ),
    );
    await tester.pumpAndSettle();
    expect(storeHome('customer'), findsOneWidget);
    expect(find.text('ទិញតាមប្រភេទ'), findsOneWidget);
  });
}
