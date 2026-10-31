import 'package:flutter/material.dart';

import '../../../core/ui/k_ui.dart';
import '../domain/delivery.dart';

const _minLat = 11.49;
const _maxLat = 11.66;
const _minLng = 104.82;
const _maxLng = 105.02;

Offset _screen(GeoPoint point, Size size) => Offset(
  (point.lng - _minLng) / (_maxLng - _minLng) * size.width,
  (1 - (point.lat - _minLat) / (_maxLat - _minLat)) * size.height,
);

GeoPoint _geo(Offset offset, Size size) => GeoPoint(
  _maxLat - offset.dy.clamp(0, size.height) / size.height * (_maxLat - _minLat),
  _minLng + offset.dx.clamp(0, size.width) / size.width * (_maxLng - _minLng),
);

class DeliveryMap extends StatelessWidget {
  const DeliveryMap({
    super.key,
    this.zones = const [],
    this.pin,
    this.editingZone,
    this.onPinChanged,
    this.onZoneChanged,
    this.height = 280,
  });

  final List<DeliveryZone> zones;
  final GeoPoint? pin;
  final DeliveryZone? editingZone;
  final ValueChanged<GeoPoint>? onPinChanged;
  final ValueChanged<List<List<GeoPoint>>>? onZoneChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, height);
        return GestureDetector(
          key: const Key('delivery-map'),
          onTapDown: onPinChanged == null
              ? null
              : (event) => onPinChanged!(_geo(event.localPosition, size)),
          onPanUpdate: editingZone == null || onZoneChanged == null
              ? null
              : (event) {
                  final rings = [
                    for (final ring in editingZone!.rings) [...ring],
                  ];
                  if (rings.isEmpty || rings.first.isEmpty) return;
                  var best = 0;
                  var distance = double.infinity;
                  for (var i = 0; i < rings.first.length; i++) {
                    final d = (_screen(rings.first[i], size) - event.localPosition)
                        .distance;
                    if (d < distance) {
                      distance = d;
                      best = i;
                    }
                  }
                  if (distance <= 36) {
                    rings.first[best] = _geo(event.localPosition, size);
                    if (best == 0 && rings.first.length > 1) {
                      rings.first[rings.first.length - 1] = rings.first.first;
                    } else if (best == rings.first.length - 1) {
                      rings.first[0] = rings.first.last;
                    }
                    onZoneChanged!(rings);
                  }
                },
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _DeliveryMapPainter(
                zones: zones,
                pin: pin,
                editingZoneId: editingZone?.id,
                primary: c.primary,
                line: c.line,
                ink: c.ink2,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DeliveryMapPainter extends CustomPainter {
  const _DeliveryMapPainter({
    required this.zones,
    required this.pin,
    required this.editingZoneId,
    required this.primary,
    required this.line,
    required this.ink,
  });
  final List<DeliveryZone> zones;
  final GeoPoint? pin;
  final String? editingZoneId;
  final Color primary;
  final Color line;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xffEFF6F9));
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    for (final y in [0.2, 0.48, 0.76]) {
      canvas.drawLine(Offset(0, size.height * y), Offset(size.width, size.height * y), road);
    }
    for (final x in [0.18, 0.42, 0.68, 0.86]) {
      canvas.drawLine(Offset(size.width * x, 0), Offset(size.width * x, size.height), road);
    }
    for (final zone in zones) {
      for (final ring in zone.rings) {
        if (ring.length < 3) continue;
        final path = Path()..moveTo(_screen(ring.first, size).dx, _screen(ring.first, size).dy);
        for (final point in ring.skip(1)) {
          final o = _screen(point, size);
          path.lineTo(o.dx, o.dy);
        }
        path.close();
        final active = zone.active;
        canvas.drawPath(path, Paint()..color = active ? primary.withValues(alpha: .16) : line.withValues(alpha: .45));
        canvas.drawPath(
          path,
          Paint()
            ..color = active ? primary : ink
            ..strokeWidth = zone.id == editingZoneId ? 3 : 1.5
            ..style = PaintingStyle.stroke,
        );
        if (zone.id == editingZoneId) {
          for (final point in ring) {
            final o = _screen(point, size);
            canvas.drawCircle(o, 7, Paint()..color = Colors.white);
            canvas.drawCircle(o, 7, Paint()..color = primary..style = PaintingStyle.stroke..strokeWidth = 2);
          }
        }
      }
    }
    if (pin != null) {
      final o = _screen(pin!, size);
      canvas.drawCircle(o + const Offset(0, 14), 7, Paint()..color = Colors.black.withValues(alpha: .18));
      canvas.drawCircle(o, 16, Paint()..color = primary);
      canvas.drawCircle(o, 6, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _DeliveryMapPainter old) =>
      old.zones != zones || old.pin != pin || old.editingZoneId != editingZoneId;
}

