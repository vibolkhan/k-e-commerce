class GeoPoint {
  const GeoPoint(this.lat, this.lng);
  final double lat;
  final double lng;

  Map<String, dynamic> toCoordinate() => {'lat': lat, 'lng': lng};
}

class DeliveryAddress {
  const DeliveryAddress({
    required this.id,
    required this.label,
    required this.line,
    required this.city,
    required this.point,
    this.recipientName,
    this.phone,
    this.note,
    this.zoneId,
    this.zoneName,
    this.isDefault = false,
  });

  factory DeliveryAddress.fromRow(Map<String, dynamic> row) {
    final zone = row['delivery_zones'];
    return DeliveryAddress(
      id: row['id'] as String,
      label: row['label'] as String? ?? '',
      line: row['line'] as String? ?? '',
      city: row['city'] as String? ?? 'Phnom Penh',
      point: GeoPoint(
        (row['lat'] as num?)?.toDouble() ?? 0,
        (row['lng'] as num?)?.toDouble() ?? 0,
      ),
      recipientName: row['recipient_name'] as String?,
      phone: row['phone'] as String?,
      note: row['note'] as String?,
      zoneId: row['zone_id'] as String?,
      zoneName: zone is Map ? zone['name'] as String? : null,
      isDefault: row['is_default'] as bool? ?? false,
    );
  }

  final String id;
  final String label;
  final String line;
  final String city;
  final GeoPoint point;
  final String? recipientName;
  final String? phone;
  final String? note;
  final String? zoneId;
  final String? zoneName;
  final bool isDefault;

  String get displayLine => '$line, $city';
}

class AddressDraft {
  const AddressDraft({
    this.id,
    required this.label,
    required this.line,
    required this.city,
    required this.point,
    required this.recipientName,
    required this.phone,
    this.note,
    this.isDefault = false,
  });
  final String? id;
  final String label;
  final String line;
  final String city;
  final GeoPoint point;
  final String recipientName;
  final String phone;
  final String? note;
  final bool isDefault;
}

class DeliveryZone {
  const DeliveryZone({
    required this.id,
    required this.name,
    required this.rings,
    required this.feeCents,
    required this.freeThresholdCents,
    required this.sameDay,
    required this.codEnabled,
    required this.codLimitCents,
    required this.active,
    this.sort = 0,
  });

  factory DeliveryZone.fromJson(Map<String, dynamic> json) {
    final polygon = json['polygon'] as Map<String, dynamic>? ?? const {};
    final raw = polygon['coordinates'] as List? ?? const [];
    final multi = polygon['type'] == 'Polygon' ? [raw] : raw;
    final rings = <List<GeoPoint>>[];
    for (final shape in multi) {
      if (shape is! List || shape.isEmpty || shape.first is! List) continue;
      rings.add([
        for (final point in shape.first as List)
          if (point is List && point.length >= 2)
            GeoPoint((point[1] as num).toDouble(), (point[0] as num).toDouble()),
      ]);
    }
    return DeliveryZone(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      rings: rings,
      feeCents: (json['fee_cents'] as num?)?.toInt() ?? 0,
      freeThresholdCents:
          (json['free_threshold_cents'] as num?)?.toInt() ?? 0,
      sameDay: json['same_day'] as bool? ?? false,
      codEnabled: json['cod_enabled'] as bool? ?? false,
      codLimitCents: (json['cod_limit_cents'] as num?)?.toInt() ?? 0,
      active: json['active'] as bool? ?? false,
      sort: (json['sort'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final List<List<GeoPoint>> rings;
  final int feeCents;
  final int freeThresholdCents;
  final bool sameDay;
  final bool codEnabled;
  final int codLimitCents;
  final bool active;
  final int sort;

  Map<String, dynamic> get polygonJson => {
    'type': 'MultiPolygon',
    'coordinates': [
      for (final ring in rings)
        [
          for (final point in ring) [point.lng, point.lat],
        ],
    ],
  };

  DeliveryZone copyWith({
    String? name,
    List<List<GeoPoint>>? rings,
    int? feeCents,
    int? freeThresholdCents,
    bool? sameDay,
    bool? codEnabled,
    int? codLimitCents,
    bool? active,
  }) => DeliveryZone(
    id: id,
    name: name ?? this.name,
    rings: rings ?? this.rings,
    feeCents: feeCents ?? this.feeCents,
    freeThresholdCents: freeThresholdCents ?? this.freeThresholdCents,
    sameDay: sameDay ?? this.sameDay,
    codEnabled: codEnabled ?? this.codEnabled,
    codLimitCents: codLimitCents ?? this.codLimitCents,
    active: active ?? this.active,
    sort: sort,
  );
}

sealed class DeliveryQuote {
  const DeliveryQuote();
  factory DeliveryQuote.fromJson(Map<String, dynamic> json) =>
      switch (json['status']) {
        'available' => AvailableDeliveryQuote(
          zoneId: json['zone_id'] as String,
          zoneName: json['zone_name'] as String,
          feeCents: (json['fee_cents'] as num).toInt(),
          sameDayEligible: json['same_day_eligible'] as bool,
          codAllowed: json['cod_allowed'] as bool,
          codLimitCents: (json['cod_limit_cents'] as num).toInt(),
        ),
        _ => const OutOfZoneDeliveryQuote(),
      };
}

class AvailableDeliveryQuote extends DeliveryQuote {
  const AvailableDeliveryQuote({
    required this.zoneId,
    required this.zoneName,
    required this.feeCents,
    required this.sameDayEligible,
    required this.codAllowed,
    required this.codLimitCents,
  });
  final String zoneId;
  final String zoneName;
  final int feeCents;
  final bool sameDayEligible;
  final bool codAllowed;
  final int codLimitCents;
}

class OutOfZoneDeliveryQuote extends DeliveryQuote {
  const OutOfZoneDeliveryQuote();
}
