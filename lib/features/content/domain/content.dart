import '../../catalog/domain/i18n_text.dart';

enum ContentAudience { all, retail, business }

enum BannerState { live, scheduled, ended, hidden }

class AdminBanner {
  const AdminBanner({
    required this.id,
    required this.title,
    this.subtitle = I18nText.empty,
    this.cta = I18nText.empty,
    this.badge = I18nText.empty,
    this.imagePath,
    this.linkType,
    this.linkTarget,
    this.audience = ContentAudience.all,
    this.startsAt,
    this.endsAt,
    this.active = true,
    this.sort = 0,
  });

  factory AdminBanner.fromRow(Map<String, dynamic> row) => AdminBanner(
    id: row['id'] as String,
    title: I18nText.fromJson(row['title']),
    subtitle: I18nText.fromJson(row['subtitle']),
    cta: I18nText.fromJson(row['cta']),
    badge: I18nText.fromJson(row['badge']),
    imagePath: row['image_path'] as String?,
    linkType: row['link_type'] as String?,
    linkTarget: row['link_target'] as String?,
    audience: ContentAudience.values.byName(
      row['audience'] as String? ?? 'all',
    ),
    startsAt: DateTime.tryParse(row['starts_at'] as String? ?? ''),
    endsAt: DateTime.tryParse(row['ends_at'] as String? ?? ''),
    active: row['active'] as bool? ?? true,
    sort: (row['sort'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final I18nText title, subtitle, cta, badge;
  final String? imagePath, linkType, linkTarget;
  final ContentAudience audience;
  final DateTime? startsAt, endsAt;
  final bool active;
  final int sort;

  BannerState stateAt(DateTime now) {
    if (!active) return BannerState.hidden;
    if (startsAt != null && startsAt!.isAfter(now)) {
      return BannerState.scheduled;
    }
    if (endsAt != null && !endsAt!.isAfter(now)) return BannerState.ended;
    return BannerState.live;
  }

  Map<String, dynamic> toRow() => {
    'title': title.toJson(),
    'subtitle': subtitle.toJson(),
    'cta': cta.toJson(),
    'badge': badge.toJson(),
    'image_path': imagePath,
    'link_type': linkType,
    'link_target': linkTarget,
    'audience': audience.name,
    'starts_at': startsAt?.toUtc().toIso8601String(),
    'ends_at': endsAt?.toUtc().toIso8601String(),
    'active': active,
    'sort': sort,
  };
}

class AdminCollection {
  const AdminCollection({
    required this.id,
    required this.slug,
    required this.title,
    this.audience = ContentAudience.all,
    this.active = true,
    this.sort = 0,
  });
  factory AdminCollection.fromRow(Map<String, dynamic> row) => AdminCollection(
    id: row['id'] as String,
    slug: row['slug'] as String,
    title: I18nText.fromJson(row['title']),
    audience: ContentAudience.values.byName(
      row['audience'] as String? ?? 'all',
    ),
    active: row['active'] as bool? ?? true,
    sort: (row['sort'] as num?)?.toInt() ?? 0,
  );
  final String id, slug;
  final I18nText title;
  final ContentAudience audience;
  final bool active;
  final int sort;
  Map<String, dynamic> toRow() => {
    'slug': slug,
    'title': title.toJson(),
    'audience': audience.name,
    'active': active,
    'sort': sort,
  };
}

class ContentPageModel {
  const ContentPageModel({
    required this.id,
    required this.slug,
    required this.title,
    required this.body,
    this.published = false,
  });
  factory ContentPageModel.fromRow(Map<String, dynamic> row) =>
      ContentPageModel(
        id: row['id'] as String,
        slug: row['slug'] as String,
        title: I18nText.fromJson(row['title']),
        body: I18nText.fromJson(row['body']),
        published: row['published'] as bool? ?? false,
      );
  final String id, slug;
  final I18nText title, body;
  final bool published;
  Map<String, dynamic> toRow() => {
    'slug': slug,
    'title': title.toJson(),
    'body': body.toJson(),
    'published': published,
  };
}
