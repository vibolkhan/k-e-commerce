import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/delivery_repository.dart';
import '../domain/delivery.dart';

final addressesProvider = FutureProvider.autoDispose<List<DeliveryAddress>>(
  (ref) => ref.watch(deliveryRepositoryProvider).addresses(),
);

final deliveryZonesProvider = FutureProvider.autoDispose<List<DeliveryZone>>(
  (ref) => ref.watch(deliveryRepositoryProvider).zones(),
);

