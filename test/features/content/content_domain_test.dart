import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/features/catalog/domain/i18n_text.dart';
import 'package:k_e_commerce/features/content/domain/content.dart';

void main() {
  final now = DateTime.utc(2026, 10, 28, 8);

  AdminBanner banner({bool active = true, DateTime? start, DateTime? end}) =>
      AdminBanner(
        id: 'b1',
        title: const I18nText(en: 'Banner'),
        active: active,
        startsAt: start,
        endsAt: end,
      );

  test('banner state is evaluated at the supplied server-aligned time', () {
    expect(banner().stateAt(now), BannerState.live);
    expect(banner(active: false).stateAt(now), BannerState.hidden);
    expect(
      banner(start: now.add(const Duration(minutes: 1))).stateAt(now),
      BannerState.scheduled,
    );
    expect(banner(end: now).stateAt(now), BannerState.ended);
  });

  test('banner persistence uses UTC schedule and bilingual copy', () {
    final row = AdminBanner(
      id: 'b1',
      title: const I18nText(en: 'Sale', km: 'ការបញ្ចុះតម្លៃ'),
      startsAt: DateTime.parse('2026-11-01T08:00:00+07:00'),
      audience: ContentAudience.business,
    ).toRow();
    expect(row['title'], {'en': 'Sale', 'km': 'ការបញ្ចុះតម្លៃ'});
    expect(row['audience'], 'business');
    expect(row['starts_at'], '2026-11-01T01:00:00.000Z');
  });
}
