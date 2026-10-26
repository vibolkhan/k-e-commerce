import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:k_e_commerce/core/l10n/generated/app_localizations.dart';
import 'package:k_e_commerce/features/notifications/data/push_service.dart';
import 'package:k_e_commerce/features/notifications/domain/app_notification.dart';
import 'package:k_e_commerce/features/notifications/domain/notification_prefs.dart';
import 'package:k_e_commerce/features/notifications/presentation/notification_style.dart';

import 'fakes.dart';

void main() {
  group('inbox rows', () {
    test('read from the database row, copy per language', () {
      final n = AppNotification.fromRow({
        'id': 'n1',
        'type': 'quote_ready',
        'category': 'quotes',
        'title': {
          'en': 'Your quote is ready',
          'km': 'សម្រង់តម្លៃរបស់អ្នករួចរាល់ហើយ',
        },
        'body': {'en': 'RFQ-0312 · \$2,260.50'},
        'payload': {'route': '/business/quotes/$rfqId', 'rfq_id': rfqId},
        'created_at': '2026-10-26T06:42:00+00:00',
        'read_at': null,
      });
      expect(n.category, NotificationCategory.quotes);
      expect(n.isUnread, isTrue);
      expect(n.route, '/business/quotes/$rfqId');
      expect(n.titleIn('km'), 'សម្រង់តម្លៃរបស់អ្នករួចរាល់ហើយ');
      // No Khmer body: English rather than nothing.
      expect(n.bodyIn('km'), 'RFQ-0312 · \$2,260.50');
      expect(n.markedRead(DateTime.utc(2026)).isUnread, isFalse);
    });

    test('an unknown category files under Orders', () {
      expect(NotificationCategory.parse('promo'), NotificationCategory.orders);
      expect(NotificationCategory.parse(null), NotificationCategory.orders);
    });

    test('tabs: All shows everything, Account items only under All', () {
      final at = DateTime.utc(2026, 10, 26);
      final account = notification(
        't',
        type: 'test',
        category: NotificationCategory.account,
        at: at,
      );
      final chat = notification(
        'c',
        category: NotificationCategory.chat,
        at: at,
      );
      expect(InboxTab.all.shows(account), isTrue);
      expect(InboxTab.values.where((tab) => tab.shows(account)), [
        InboxTab.all,
      ]);
      expect(InboxTab.chat.shows(chat), isTrue);
      expect(InboxTab.orders.shows(chat), isFalse);
    });
  });

  group('only in-app paths reach the router', () {
    test('accepted', () {
      expect(
        safeRoute('/customer/orders/$orderId'),
        '/customer/orders/$orderId',
      );
      expect(safeRoute('/customer/inbox'), '/customer/inbox');
    });

    test('refused', () {
      expect(safeRoute('https://evil.example/'), isNull);
      expect(safeRoute('//evil.example/x'), isNull);
      expect(safeRoute('customer/inbox'), isNull);
      expect(safeRoute(42), isNull);
      expect(safeRoute(null), isNull);
    });

    test('push data without a safe route is ignored', () {
      expect(PushTap.fromData({'route': '//x'}), isNull);
      final tap = PushTap.fromData({
        'route': '/customer/inbox',
        'notification_id': 'n1',
      })!;
      expect((tap.route, tap.notificationId), ('/customer/inbox', 'n1'));
    });
  });

  group('S-08d switches', () {
    test('defaults: everything on except review reminders', () {
      const prefs = NotificationPrefs();
      for (final group in NotificationGroup.values) {
        expect(
          prefs.isOn(group, NotificationChannel.push),
          group != NotificationGroup.reviews,
          reason: group.name,
        );
      }
      expect(
        prefs.isOn(NotificationGroup.orders, NotificationChannel.email),
        isTrue,
      );
    });

    test('a change keeps the rest, including keys this app does not know', () {
      final prefs = NotificationPrefs.fromJson({
        'orders': {'push': true, 'email': false},
        'marketing': {'push': false},
      }).withValue(NotificationGroup.orders, NotificationChannel.push, false);
      expect(prefs.toJson(), {
        'orders': {'push': false, 'email': false},
        'marketing': {'push': false},
      });
    });

    test('garbage reads as defaults', () {
      final prefs = NotificationPrefs.fromJson(['nope']);
      expect(
        prefs.isOn(NotificationGroup.chat, NotificationChannel.push),
        isTrue,
      );
      final odd = NotificationPrefs.fromJson({
        'chat': {'push': 'yes'},
      });
      expect(
        odd.isOn(NotificationGroup.chat, NotificationChannel.push),
        isTrue,
      );
    });
  });

  group('inbox time and groups (Phnom Penh)', () {
    setUpAll(initializeDateFormatting);
    // 2026-10-26 13:55 in Phnom Penh.
    final now = DateTime.utc(2026, 10, 26, 6, 55);
    final en = lookupAppLocalizations(const Locale('en'));

    test('today shows the time, then Yesterday, then the date', () {
      expect(
        inboxTimeLabel(en, DateTime.utc(2026, 10, 26, 6, 50), now: now),
        '1:50 PM',
      );
      // 23:30 UTC on the 25th is 6:30 AM on the 26th in Phnom Penh.
      expect(
        inboxTimeLabel(en, DateTime.utc(2026, 10, 25, 23, 30), now: now),
        '6:30 AM',
      );
      expect(
        inboxTimeLabel(en, DateTime.utc(2026, 10, 25, 10), now: now),
        'Yesterday',
      );
      expect(
        inboxTimeLabel(en, DateTime.utc(2026, 10, 21, 10), now: now),
        '21 Oct',
      );
      expect(
        inboxTimeLabel(
          lookupAppLocalizations(const Locale('km')),
          DateTime.utc(2026, 10, 25, 10),
          now: now,
        ),
        'ម្សិលមិញ',
      );
    });

    test('Today and Earlier split at Phnom Penh midnight', () {
      final groups = groupByDay([
        notification('a', at: DateTime.utc(2026, 10, 26, 1)),
        notification('b', at: DateTime.utc(2026, 10, 25, 17, 30)),
        notification('c', at: DateTime.utc(2026, 10, 25, 16, 30)),
      ], now: now);
      expect(groups.today.map((n) => n.id), ['a', 'b']);
      expect(groups.earlier.map((n) => n.id), ['c']);
    });
  });
}
