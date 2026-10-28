import '../../../core/time/cutoff.dart';
import '../../../core/time/phnom_penh_time.dart';
import '../../catalog/domain/i18n_text.dart';
import 'browse.dart';

/// A category as shoppers see it (CAT-02): tree position, icon key and
/// optional banner.
class StoreCategory {
  const StoreCategory({
    required this.id,
    required this.slug,
    required this.name,
    this.parentId,
    this.icon,
    this.bannerUrl,
    this.sort = 0,
  });

  factory StoreCategory.fromRow(
    Map<String, dynamic> row, {
    required String Function(String path) bannerUrl,
  }) {
    final banner = row['banner_path'] as String?;
    return StoreCategory(
      id: row['id'] as String,
      slug: row['slug'] as String? ?? '',
      name: I18nText.fromJson(row['name']),
      parentId: row['parent_id'] as String?,
      icon: row['icon'] as String?,
      bannerUrl: banner == null || banner.isEmpty ? null : bannerUrl(banner),
      sort: (row['sort'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String slug;
  final I18nText name;
  final String? parentId;

  /// Icon key set in A-05 (e.g. `headphones`, `shirt`).
  final String? icon;
  final String? bannerUrl;
  final int sort;

  bool get isTop => parentId == null;
}

/// The category tree, in display order.
class CategoryTree {
  CategoryTree(List<StoreCategory> all)
    : _all = [...all]..sort((a, b) => a.sort.compareTo(b.sort));

  final List<StoreCategory> _all;

  List<StoreCategory> get top => [
    for (final c in _all)
      if (c.isTop) c,
  ];

  List<StoreCategory> childrenOf(String id) => [
    for (final c in _all)
      if (c.parentId == id) c,
  ];

  StoreCategory? bySlug(String slug) {
    for (final c in _all) {
      if (c.slug == slug) return c;
    }
    return null;
  }

  StoreCategory? byId(String id) {
    for (final c in _all) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Home "Shop by category": top categories first, then their children,
  /// so the grid fills with what shoppers browse most.
  List<StoreCategory> shortcuts(int count) =>
      [...top, for (final t in top) ...childrenOf(t.id)].take(count).toList();

  bool get isEmpty => _all.isEmpty;
}

/// Where a banner's button goes (`banners.link_type`).
enum BannerLinkType { collection, category, product, page, url }

/// A home banner (CAT-06), managed in A-12.
class HomeBanner {
  const HomeBanner({
    required this.id,
    required this.title,
    this.subtitle = I18nText.empty,
    this.cta = I18nText.empty,
    this.badge = I18nText.empty,
    this.imageUrl,
    this.linkType,
    this.linkTarget,
  });

  factory HomeBanner.fromRow(
    Map<String, dynamic> row, {
    required String Function(String path) imageUrl,
  }) {
    final path = bannerStoragePath(row['image_path'] as String?);
    return HomeBanner(
      id: row['id'] as String,
      title: I18nText.fromJson(row['title']),
      subtitle: I18nText.fromJson(row['subtitle']),
      cta: I18nText.fromJson(row['cta']),
      badge: I18nText.fromJson(row['badge']),
      imageUrl: path == null ? null : imageUrl(path),
      linkType: BannerLinkType.values
          .where((t) => t.name == row['link_type'])
          .firstOrNull,
      linkTarget: row['link_target'] as String?,
    );
  }

  final String id;
  final I18nText title;
  final I18nText subtitle;
  final I18nText cta;
  final I18nText badge;
  final String? imageUrl;
  final BannerLinkType? linkType;
  final String? linkTarget;
}

/// `banners.image_path` is relative to the `banners` bucket; some rows carry
/// the bucket name as a prefix. Null when there is no image.
String? bannerStoragePath(String? path) {
  final p = path?.trim() ?? '';
  if (p.isEmpty) return null;
  return p.startsWith('banners/') ? p.substring('banners/'.length) : p;
}

/// The home screen's curated content, per audience.
class HomeContent {
  const HomeContent({
    this.banners = const [],
    this.featured = const [],
    this.fresh = const [],
  });

  final List<HomeBanner> banners;

  /// Best sellers (retail) or Popular for offices (business).
  final List<BrowseItem> featured;

  /// New arrivals.
  final List<BrowseItem> fresh;
}

/// The home collections for each audience.
abstract final class HomeCollections {
  static const bestSellers = 'best-sellers';
  static const newArrivals = 'new-arrivals';
  static const popularForOffices = 'popular-for-offices';

  static String featured(Audience audience) =>
      audience == Audience.business ? popularForOffices : bestSellers;
}

/// What the server says about time: its clock, the cut-off and the
/// no-delivery days (`storefront_clock`).
class StoreClock {
  const StoreClock({
    required this.serverNow,
    required this.cutoff,
    this.holidays = const {},
    required this.fetchedAt,
  });

  factory StoreClock.fromJson(Map<String, dynamic> json, DateTime fetchedAt) =>
      StoreClock(
        serverNow: DateTime.parse(json['now'] as String),
        cutoff: Cutoff.parse(json['cutoff'] as String?),
        holidays: {
          for (final h in json['holidays'] as List? ?? const []) h.toString(),
        },
        fetchedAt: fetchedAt,
      );

  /// Until the server answers: the device clock and the standard cut-off.
  factory StoreClock.local(DateTime now) =>
      StoreClock(serverNow: now, cutoff: Cutoff.standard, fetchedAt: now);

  final DateTime serverNow;
  final Cutoff cutoff;

  /// `yyyy-MM-dd` Phnom Penh dates with no deliveries.
  final Set<String> holidays;

  /// Device time when [serverNow] was read.
  final DateTime fetchedAt;

  /// Server time now, from the device clock plus the measured offset.
  DateTime nowFrom(DateTime deviceNow) =>
      serverNow.add(deviceNow.difference(fetchedAt));
}

/// The same-day promise at a moment: order within [remaining] for today, or
/// delivery on [nextDay].
sealed class SameDayStatus {
  const SameDayStatus();

  /// [now] is server time. Before the cut-off on a delivery day: today.
  /// Otherwise the next day that isn't a holiday.
  factory SameDayStatus.at(DateTime now, StoreClock clock) {
    final local = toPhnomPenh(now);
    final today = DateTime.utc(local.year, local.month, local.day);
    final left = clock.cutoff.remaining(now);
    if (left != null && !clock.holidays.contains(_ymd(today))) {
      return SameDayOpen(left);
    }
    var day = today.add(const Duration(days: 1));
    for (var i = 0; i < 14 && clock.holidays.contains(_ymd(day)); i++) {
      day = day.add(const Duration(days: 1));
    }
    return SameDayClosed(day, isTomorrow: day.difference(today).inDays == 1);
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class SameDayOpen extends SameDayStatus {
  const SameDayOpen(this.remaining);
  final Duration remaining;
}

class SameDayClosed extends SameDayStatus {
  const SameDayClosed(this.nextDay, {required this.isTomorrow});

  /// Phnom Penh calendar date (UTC fields) of the next delivery day.
  final DateTime nextDay;
  final bool isTomorrow;
}

/// The "Deliver to" pill: a saved address, or the city for guests and
/// shoppers with no address yet.
class DeliverTo {
  const DeliverTo({required this.id, required this.label, this.area});

  final String id;

  /// "Home", "Office".
  final String label;

  /// The delivery zone name, e.g. "Toul Kork".
  final String? area;
}
