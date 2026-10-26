import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/app.dart';
import 'package:k_e_commerce/core/config/app_config.dart';
import 'package:k_e_commerce/core/config/bootstrap.dart';
import 'package:k_e_commerce/core/router/app_role.dart';
import 'package:k_e_commerce/core/router/app_router.dart';
import 'package:k_e_commerce/core/router/app_routes.dart';
import 'package:k_e_commerce/features/design_gallery/presentation/design_gallery_page.dart';

import '../../helpers.dart';

void main() {
  group('roleRedirect', () {
    test('root goes to the role home', () {
      for (final role in AppRole.values) {
        expect(roleRedirect(role, AppRoutes.root), role.homePath);
      }
    });

    test('own shell is allowed, including sub-paths', () {
      expect(roleRedirect(AppRole.rider, AppRoutes.rider), isNull);
      expect(roleRedirect(AppRole.rider, '${AppRoutes.rider}/jobs'), isNull);
    });

    test('other shells are forbidden', () {
      expect(
        roleRedirect(AppRole.customer, AppRoutes.admin),
        AppRoutes.forbidden,
      );
      expect(
        roleRedirect(AppRole.admin, '${AppRoutes.customer}/cart'),
        AppRoutes.forbidden,
      );
    });

    test('shared pages are open to every role', () {
      expect(roleRedirect(AppRole.rider, AppRoutes.loading), isNull);
      expect(roleRedirect(AppRole.rider, AppRoutes.forbidden), isNull);
    });
  });

  group('router', () {
    Future<ProviderContainer> pumpApp(
      WidgetTester tester, {
      AppEnv env = AppEnv.dev,
    }) async {
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig(env: env, supabaseUrl: '', supabaseAnonKey: ''),
          ),
          onboardedDevice,
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const KApp()),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('opens the customer shell by default', (tester) async {
      await pumpApp(tester);
      expect(find.text('Customer home'), findsOneWidget);
    });

    testWidgets('unknown path shows not found', (tester) async {
      final container = await pumpApp(tester);
      container.read(routerProvider).go('/nope');
      await tester.pumpAndSettle();
      expect(find.text('Page not found'), findsOneWidget);
    });

    testWidgets('other role shell shows no access', (tester) async {
      final container = await pumpApp(tester);
      container.read(routerProvider).go(AppRoutes.admin);
      await tester.pumpAndSettle();
      expect(find.text('No access'), findsOneWidget);

      await tester.tap(find.text('Go home'));
      await tester.pumpAndSettle();
      expect(find.text('Customer home'), findsOneWidget);
    });

    testWidgets('changing role moves to that shell', (tester) async {
      final container = await pumpApp(tester);
      container.read(currentRoleProvider.notifier).set(AppRole.admin);
      await tester.pumpAndSettle();
      expect(find.text('Admin home'), findsOneWidget);
    });

    testWidgets('debug role switcher opens each shell', (tester) async {
      await pumpApp(tester);
      for (final label in ['Business', 'Rider', 'Admin', 'Customer']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text('$label home'), findsOneWidget);
      }
    });

    testWidgets('design gallery opens for any role outside prod', (
      tester,
    ) async {
      final container = await pumpApp(tester, env: AppEnv.staging);
      container.read(currentRoleProvider.notifier).set(AppRole.rider);
      await tester.pumpAndSettle();
      container.read(routerProvider).go(AppRoutes.designGallery);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(DesignGalleryPage), findsOneWidget);
    });

    testWidgets('design gallery is not found in prod', (tester) async {
      final container = await pumpApp(tester, env: AppEnv.prod);
      container.read(routerProvider).go(AppRoutes.designGallery);
      await tester.pumpAndSettle();
      expect(find.byType(DesignGalleryPage), findsNothing);
      expect(find.text('Page not found'), findsOneWidget);
    });
  });
}
