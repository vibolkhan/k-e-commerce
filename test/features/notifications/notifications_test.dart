import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/app.dart';
import 'package:k_e_commerce/core/config/app_config.dart';
import 'package:k_e_commerce/core/config/bootstrap.dart';
import 'package:k_e_commerce/core/router/app_role.dart';
import 'package:k_e_commerce/core/router/app_router.dart';
import 'package:k_e_commerce/core/router/app_routes.dart';
import 'package:k_e_commerce/core/time/phnom_penh_time.dart';
import 'package:k_e_commerce/core/ui/k_ui.dart';
import 'package:k_e_commerce/features/account/presentation/account_page.dart';
import 'package:k_e_commerce/features/auth/domain/profile.dart';
import 'package:k_e_commerce/features/auth/presentation/auth_providers.dart';
import 'package:k_e_commerce/features/notifications/data/push_service.dart';
import 'package:k_e_commerce/features/notifications/domain/app_notification.dart';
import 'package:k_e_commerce/features/notifications/domain/notification_prefs.dart';
import 'package:k_e_commerce/features/notifications/presentation/in_app_banner.dart';
import 'package:k_e_commerce/features/notifications/presentation/notifications_providers.dart';

import '../../helpers.dart';
import '../auth/auth_harness.dart';
import '../auth/fake_auth_repository.dart';
import 'fakes.dart';

const _dara = Profile(
  id: 'c',
  role: AppRole.customer,
  fullName: 'Dara Sok',
  phone: '+85512345678',
);
const _sokha = Profile(
  id: 'b',
  role: AppRole.business,
  fullName: 'Sokha Chan',
  phone: '+85512345681',
);

/// 1:55 PM on Mon 26 Oct in Phnom Penh.
final _now = DateTime.utc(2026, 10, 26, 6, 55);

/// Dara's inbox from S-07: three unread today, two read earlier.
List<AppNotification> _daraInbox() => [
  notification(
    'chat',
    type: 'chat_message',
    category: NotificationCategory.chat,
    title: 'K Support replied',
    body: 'Sophea: Your rider is about 5 minutes away.',
    route: '/customer/chat/$conversationId',
    at: _now.subtract(const Duration(minutes: 5)),
  ),
  notification('way', at: _now.subtract(const Duration(minutes: 13))),
  notification(
    'paid',
    type: 'payment_received',
    title: 'Payment received',
    body: 'We got \$92.00 by KHQR for #K-10248. Your order is confirmed.',
    at: _now.subtract(const Duration(hours: 3)),
  ),
  notification(
    'review',
    type: 'review_reminder',
    title: 'How was your order?',
    body: 'Rate Running Sneakers Air from #K-10231.',
    at: _now.subtract(const Duration(days: 1)),
    read: true,
  ),
  notification(
    'delivered',
    type: 'order_delivered',
    title: 'Order delivered',
    body: '#K-10231 was delivered at 5:30 PM.',
    at: _now.subtract(const Duration(days: 5)),
    read: true,
  ),
];

void main() {
  late FakeAuthRepository auth;
  late FakeNotificationsRepository inbox;
  late FakePushService push;

  /// The whole app, onboarded and signed in as [email] (or a guest), on the
  /// role's home.
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    String? email = 'dara@k.example',
    List<AppNotification>? rows,
    PushTap? launch,
  }) async {
    setViewSize(tester, const Size(390, 844));
    auth = FakeAuthRepository(
      accounts: {'dara@k.example': _dara, 'sokha@k.example': _sokha},
    );
    inbox = FakeNotificationsRepository(rows ?? _daraInbox());
    push = FakePushService(launch: launch);
    addTearDown(auth.dispose);
    addTearDown(inbox.dispose);
    addTearDown(push.dispose);
    if (email != null) await auth.signInWithPassword(email, 'password123');
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            env: AppEnv.dev,
            supabaseUrl: '',
            supabaseAnonKey: '',
          ),
        ),
        authRepositoryProvider.overrideWithValue(auth),
        notificationsRepositoryProvider.overrideWithValue(inbox),
        pushServiceProvider.overrideWithValue(push),
        clockProvider.overrideWithValue(() => _now),
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

  Finder bell() => find.byKey(const Key('notification-bell'));

  Future<void> openInbox(WidgetTester tester) async {
    await tester.tap(bell());
    await tester.pumpAndSettle();
  }

  /// The top route, including pushed ones.
  String path(ProviderContainer c) => c.read(routerProvider).state.uri.path;

  group('S-07 inbox', () {
    testWidgets('the bell shows a red dot and the unread count', (
      tester,
    ) async {
      await pumpApp(tester);
      final button = tester.widget<KIconButton>(bell());
      expect(button.dot, isTrue);
      expect(button.label, 'Notifications, 3 unread');
    });

    testWidgets('Today and Earlier, unread rows bold with a blue dot', (
      tester,
    ) async {
      await pumpApp(tester);
      await openInbox(tester);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('EARLIER'), findsOneWidget);
      expect(find.byKey(const Key('inbox-unread-dot')), findsNWidgets(3));
      expect(find.text('1:50 PM'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('21 Oct'), findsOneWidget);
      // All carries the unread count.
      expect(find.bySemanticsLabel('All, 3'), findsOneWidget);
      final unreadTitle = tester.widget<Text>(find.text('K Support replied'));
      final readTitle = tester.widget<Text>(find.text('Order delivered'));
      expect(unreadTitle.style!.fontWeight, FontWeight.w700);
      expect(readTitle.style!.fontWeight, FontWeight.w600);
    });

    testWidgets('tabs filter by kind', (tester) async {
      await pumpApp(tester);
      await openInbox(tester);
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      expect(find.text('K Support replied'), findsOneWidget);
      expect(find.text('Payment received'), findsNothing);

      await tester.tap(find.text('Quotes'));
      await tester.pumpAndSettle();
      expect(find.text('You’re all caught up'), findsOneWidget);

      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();
      expect(find.text('Payment received'), findsOneWidget);
      expect(find.text('K Support replied'), findsNothing);
    });

    testWidgets('a tap marks the row read and opens its screen', (
      tester,
    ) async {
      final c = await pumpApp(tester);
      await openInbox(tester);
      await tester.tap(find.byKey(const Key('inbox-row-chat')));
      await tester.pumpAndSettle();
      expect(path(c), '/customer/chat/$conversationId');
      expect(find.text('Support chat'), findsNWidgets(2));
      expect(
        find.text('This screen (C-17) arrives in a later update.'),
        findsOneWidget,
      );
      expect(inbox.read, ['chat']);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(path(c), '/customer/inbox');
      expect(find.byKey(const Key('inbox-unread-dot')), findsNWidgets(2));
    });

    testWidgets('Mark all read clears every dot and the bell', (tester) async {
      await pumpApp(tester);
      await openInbox(tester);
      await tester.tap(find.byKey(const Key('inbox-mark-all')));
      await tester.pumpAndSettle();
      expect(inbox.markAllCalls, 1);
      expect(find.byKey(const Key('inbox-unread-dot')), findsNothing);
      expect(find.bySemanticsLabel('All, 3'), findsNothing);
      final button = tester.widget<KButton>(
        find.byKey(const Key('inbox-mark-all')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Mark all read failing says so and keeps the dots', (
      tester,
    ) async {
      await pumpApp(tester);
      await openInbox(tester);
      inbox.failMarkAll = true;
      await tester.tap(find.byKey(const Key('inbox-mark-all')));
      await tester.pump();
      expect(find.text('Couldn’t mark them read. Try again.'), findsOneWidget);
      expect(find.byKey(const Key('inbox-unread-dot')), findsNWidgets(3));
      await settleToasts(tester);
    });

    testWidgets('an empty inbox is all caught up, and the bell has no dot', (
      tester,
    ) async {
      await pumpApp(tester, rows: const []);
      expect(tester.widget<KIconButton>(bell()).dot, isFalse);
      await openInbox(tester);
      expect(find.text('You’re all caught up'), findsOneWidget);
    });

    testWidgets('is in Khmer for Khmer readers', (tester) async {
      final c = await pumpApp(tester);
      await openInbox(tester);
      expect(find.text('KM K Support replied'), findsNothing);
      // Switch the UI language: rows re-render from the stored copy.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const KApp(locale: Locale('km')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('KM K Support replied'), findsOneWidget);
      expect(find.text('ថ្ងៃនេះ'), findsOneWidget);
    });

    testWidgets('guests have no bell and no inbox', (tester) async {
      final c = await pumpApp(tester, email: null);
      expect(bell(), findsNothing);
      c.read(routerProvider).go(AppRoutes.inbox(AppRoutes.customer));
      await tester.pumpAndSettle();
      expect(path(c), AppRoutes.customer);
    });

    testWidgets('customers cannot open a business quote link', (tester) async {
      final c = await pumpApp(tester);
      c.read(routerProvider).go(AppRoutes.quote(rfqId));
      await tester.pumpAndSettle();
      expect(path(c), AppRoutes.forbidden);
    });
  });

  group('S-08d notification settings', () {
    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-notifications')));
      await tester.pumpAndSettle();
    }

    Switch switchFor(WidgetTester tester, String key) => tester.widget<Switch>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Switch)),
    );

    testWidgets('customers: orders, chat and reviews; payments always sent', (
      tester,
    ) async {
      await pumpApp(tester);
      await openSettings(tester);
      expect(find.text('Orders & delivery'), findsOneWidget);
      expect(find.text('Chat messages'), findsOneWidget);
      expect(find.text('Review reminders'), findsOneWidget);
      expect(find.text('Quotes'), findsNothing);
      expect(
        find.text('Payment and security messages are always sent.'),
        findsOneWidget,
      );
      expect(switchFor(tester, 'notif-orders-push').value, isTrue);
      expect(switchFor(tester, 'notif-orders-email').value, isTrue);
      expect(switchFor(tester, 'notif-reviews-push').value, isFalse);
      expect(find.byKey(const Key('notif-chat-email')), findsNothing);
    });

    testWidgets('business buyers also get Quotes', (tester) async {
      await pumpApp(tester, email: 'sokha@k.example');
      await openSettings(tester);
      expect(find.text('Quotes'), findsOneWidget);
      expect(find.byKey(const Key('notif-quotes-push')), findsOneWidget);
    });

    testWidgets('a switch saves at once', (tester) async {
      await pumpApp(tester);
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('notif-orders-push')));
      await tester.pumpAndSettle();
      expect(switchFor(tester, 'notif-orders-push').value, isFalse);
      expect(
        inbox.prefs.isOn(NotificationGroup.orders, NotificationChannel.push),
        isFalse,
      );
      expect(
        inbox.prefs.isOn(NotificationGroup.orders, NotificationChannel.email),
        isTrue,
      );
    });

    testWidgets('a failed save flips the switch back and says so', (
      tester,
    ) async {
      await pumpApp(tester);
      await openSettings(tester);
      inbox.failSave = true;
      await tester.tap(find.byKey(const Key('notif-chat-push')));
      await tester.pump();
      await tester.pump();
      expect(switchFor(tester, 'notif-chat-push').value, isTrue);
      expect(
        find.text(
          'Couldn’t save that change. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      await settleToasts(tester);
    });

    testWidgets('dev builds can send a test push that opens an order', (
      tester,
    ) async {
      await pumpApp(tester);
      await openSettings(tester);
      final send = find.byKey(const Key('notif-test-send'));
      await tester.ensureVisible(send);
      await tester.tap(find.text('Order K-10248'));
      await tester.pump();
      await tester.tap(send);
      await tester.pump();
      expect(inbox.tests.single.target, 'order');
      expect(inbox.tests.single.id, orderId);
      expect(inbox.tests.single.delay, const Duration(seconds: 10));
      expect(find.text('Order K-10248'), findsOneWidget);
      // Quotes are business-only.
      expect(find.text('Quote RFQ-0312'), findsNothing);
      await settleToasts(tester);
    });
  });

  group('N-03a in-app banner', () {
    AppNotification arriving() => notification(
      'new',
      title: 'Out for delivery',
      body: '#K-10248 · Vuthy is on the way',
      at: _now,
    );

    testWidgets('slides in for 5 seconds with Track, then goes', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.byType(InAppBanner), findsNothing);
      inbox.deliver(arriving());
      await tester.pumpAndSettle();
      expect(find.text('Out for delivery'), findsOneWidget);
      expect(find.text('Track'), findsOneWidget);
      await tester.pump(bannerDuration);
      await tester.pumpAndSettle();
      expect(find.byType(InAppBanner), findsNothing);
    });

    testWidgets('its action opens the order and marks it read', (tester) async {
      final c = await pumpApp(tester);
      inbox.deliver(arriving());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('in-app-banner-action')));
      await tester.pumpAndSettle();
      expect(path(c), '/customer/orders/$orderId');
      expect(inbox.read, ['new']);
      expect(find.byType(InAppBanner), findsNothing);
    });

    testWidgets('can be swiped away', (tester) async {
      await pumpApp(tester);
      inbox.deliver(arriving());
      await tester.pumpAndSettle();
      await tester.fling(
        find.byKey(const Key('in-app-banner')),
        const Offset(0, -300),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.byType(InAppBanner), findsNothing);
      expect(inbox.read, isEmpty);
    });

    testWidgets('not for rows already there or old ones, nor on the inbox', (
      tester,
    ) async {
      await pumpApp(tester);
      // A reconnect bringing an old row.
      inbox.deliver(
        notification('old', at: _now.subtract(const Duration(hours: 1))),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InAppBanner), findsNothing);

      await openInbox(tester);
      inbox.deliver(arriving());
      await tester.pumpAndSettle();
      expect(find.byType(InAppBanner), findsNothing);
      expect(find.text('Out for delivery'), findsOneWidget);
    });
  });

  group('push (NOT-01)', () {
    testWidgets('signing in registers this device', (tester) async {
      await pumpApp(tester);
      expect(push.enabled, 1);
      expect(inbox.devices, {'fcm-token-1': 'android'});
      push.rotate('fcm-token-2');
      await tester.pump();
      expect(inbox.devices['fcm-token-2'], 'android');
    });

    testWidgets('guests are not asked for permission', (tester) async {
      await pumpApp(tester, email: null);
      expect(push.enabled, 0);
      expect(inbox.devices, isEmpty);
    });

    testWidgets('a tapped push opens its screen and marks the row read', (
      tester,
    ) async {
      final c = await pumpApp(tester);
      push.tap(
        const PushTap(
          route: '/customer/orders/$orderId',
          notificationId: 'way',
        ),
      );
      await tester.pumpAndSettle();
      expect(path(c), '/customer/orders/$orderId');
      expect(
        find.text('This screen (C-12) arrives in a later update.'),
        findsOneWidget,
      );
      expect(inbox.read, ['way']);
      // Opened straight from a push: back goes to the shell's home.
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(path(c), AppRoutes.customer);
    });

    testWidgets('a push that launched the app opens after launch', (
      tester,
    ) async {
      final c = await pumpApp(
        tester,
        launch: const PushTap(
          route: '/customer/chat/$conversationId',
          notificationId: 'chat',
        ),
      );
      expect(path(c), '/customer/chat/$conversationId');
      expect(inbox.read, ['chat']);
    });

    testWidgets('a business buyer’s quote push opens B-05', (tester) async {
      final c = await pumpApp(tester, email: 'sokha@k.example', rows: const []);
      push.tap(const PushTap(route: '/business/quotes/$rfqId'));
      await tester.pumpAndSettle();
      expect(path(c), '/business/quotes/$rfqId');
      expect(
        find.text('This screen (B-05) arrives in a later update.'),
        findsOneWidget,
      );
    });

    testWidgets('signing out removes this device first', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      final signOut = find.byKey(const Key('account-sign-out'));
      await tester.scrollUntilVisible(
        signOut,
        150,
        scrollable: find
            .descendant(
              of: find.byType(AccountPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(signOut);
      await tester.pumpAndSettle();
      await tester.tap(signOut);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(KButton, 'Sign out'));
      await tester.pumpAndSettle();
      expect(inbox.devices, isEmpty);
      expect(push.disabled, 1);
      expect(auth.signOuts, 1);
    });
  });
}
