import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/app.dart';

void main() {
  testWidgets('app shell starts and flags missing Supabase config', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: KApp()));
    await tester.pumpAndSettle();
    expect(find.text('Customer home'), findsOneWidget);
    expect(
      find.text('Supabase not configured — running offline'),
      findsOneWidget,
    );
  });

  testWidgets('app shell renders in Khmer', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: KApp(locale: Locale('km'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('ទំព័រដើម អតិថិជន'), findsOneWidget);
  });
}
