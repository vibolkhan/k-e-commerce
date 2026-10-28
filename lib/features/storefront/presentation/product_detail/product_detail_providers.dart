import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/product_detail_repository.dart';
import '../../domain/product_detail.dart';
import '../../domain/reviews.dart';

/// The product page for one product. [viewer] is `watchViewer(ref)`, so the
/// page reloads with prices when someone signs in or out.
final productDetailProvider = FutureProvider.autoDispose
    .family<ProductDetail?, ({String id, String? viewer})>(
      (ref, arg) => ref.watch(productDetailRepositoryProvider).detail(arg.id),
    );

/// The Reviews tab (C-05b); empty until F32.
final productReviewsProvider = FutureProvider.autoDispose
    .family<ProductReviews, String>(
      (ref, id) => ref.watch(reviewsRepositoryProvider).reviews(id),
    );

/// Deliveries run 9 AM – 8 PM (market rules); same-day orders arrive by
/// the end of the day.
const deliveryDayEndHour = 20;

/// Returns are accepted for this many days (market rules).
const returnWindowDays = 3;
