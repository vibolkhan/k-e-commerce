import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/phnom_penh_time.dart';
import '../../../core/utils/log.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/storefront_repository.dart';
import '../domain/browse.dart';
import '../domain/storefront.dart';

/// Home rails show this many cards.
const homeRailSize = 10;

/// The signed-in user id (null for guests). Widgets pass it into the
/// storefront families below so prices and audience follow sign-in,
/// sign-out and business approval: a new viewer is a new family member.
/// (The providers don't watch auth themselves, so a tab kept alive in the
/// background never has to catch up on a sign-out mid-build.)
String? watchViewer(WidgetRef ref) => ref.watch(authUserIdProvider).value;

final storeCategoriesProvider = FutureProvider<CategoryTree>((ref) async {
  return CategoryTree(
    await ref.watch(storefrontRepositoryProvider).categories(),
  );
});

final homeBannersProvider =
    FutureProvider.family<
      List<HomeBanner>,
      ({Audience audience, String? viewer})
    >(
      (ref, arg) =>
          ref.watch(storefrontRepositoryProvider).banners(arg.audience),
    );

/// A home rail: a collection in its curated order.
final collectionRailProvider =
    FutureProvider.family<List<BrowseItem>, ({String slug, String? viewer})>((
      ref,
      arg,
    ) async {
      final page = await ref
          .watch(storefrontRepositoryProvider)
          .browse(
            BrowseQuery(
              collection: arg.slug,
              sort: BrowseSort.curated,
              pageSize: homeRailSize,
            ),
          );
      return page.items;
    });

/// "Popular in Electronics" on C-02.
final categoryPopularProvider =
    FutureProvider.family<List<BrowseItem>, ({String id, String? viewer})>((
      ref,
      arg,
    ) async {
      final page = await ref
          .watch(storefrontRepositoryProvider)
          .browse(BrowseQuery(categoryId: arg.id, pageSize: 6));
      return page.items;
    });

/// The server clock for the countdown; the device clock until it answers
/// or if it can't be read.
final storeClockProvider = FutureProvider<StoreClock>((ref) async {
  final now = ref.read(clockProvider)();
  try {
    return await ref.watch(storefrontRepositoryProvider).clock(now);
  } catch (e) {
    log('Could not read the store clock, using the device: $e');
    return StoreClock.local(now);
  }
});

/// The shopper's saved addresses (default first); empty for guests.
final savedAddressesProvider = FutureProvider.family<List<DeliverTo>, String?>((
  ref,
  viewer,
) async {
  if (viewer == null) return const [];
  try {
    return await ref.watch(storefrontRepositoryProvider).addresses();
  } catch (e) {
    log('Could not load addresses: $e');
    return const [];
  }
});

/// The address picked in the "Deliver to" sheet for this session; null
/// means the default.
class DeliverToChoice extends Notifier<String?> {
  @override
  String? build() => null;

  void pick(String id) => state = id;
}

final deliverToChoiceProvider = NotifierProvider<DeliverToChoice, String?>(
  DeliverToChoice.new,
);

/// What the pill shows for [viewer]: the picked address, else the default,
/// else null (the city).
final deliverToProvider = Provider.family<DeliverTo?, String?>((ref, viewer) {
  final all = ref.watch(savedAddressesProvider(viewer)).value ?? const [];
  if (all.isEmpty) return null;
  final picked = ref.watch(deliverToChoiceProvider);
  return all.where((a) => a.id == picked).firstOrNull ?? all.first;
});
