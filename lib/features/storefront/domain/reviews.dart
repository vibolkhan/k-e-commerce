/// What the Reviews tab shows (C-05b): the summary bars and the latest
/// published reviews. The data arrives with F32.
class ProductReviews {
  const ProductReviews({
    this.average = 0,
    this.total = 0,
    this.byStars = const {},
    this.withPhotos = 0,
    this.items = const [],
  });

  static const none = ProductReviews();

  final double average;
  final int total;

  /// Count per star rating, 1 – 5.
  final Map<int, int> byStars;
  final int withPhotos;
  final List<Review> items;

  bool get isEmpty => total == 0 && items.isEmpty;

  /// The share of reviews with [stars], 0 – 1, for the summary bars.
  double shareOf(int stars) => total == 0 ? 0 : (byStars[stars] ?? 0) / total;
}

class Review {
  const Review({
    required this.id,
    required this.author,
    required this.rating,
    required this.createdAt,
    this.variantLabel,
    this.body = '',
    this.photoUrls = const [],
    this.reply,
    this.helpful = 0,
  });

  final String id;

  /// As shown: "Sreymom K.".
  final String author;
  final int rating;
  final DateTime createdAt;
  final String? variantLabel;
  final String body;
  final List<String> photoUrls;

  /// The public reply from K (REV-03).
  final String? reply;
  final int helpful;

  /// "SK" for the avatar.
  String get initials {
    final parts = author
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}
