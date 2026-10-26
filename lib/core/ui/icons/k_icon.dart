import 'package:flutter/widgets.dart';
import 'package:path_parsing/path_parsing.dart';

/// One element of a K icon on the 24×24 grid.
sealed class KShape {
  const KShape();
}

/// An SVG path (`d` attribute).
class KPathShape extends KShape {
  const KPathShape(this.d);
  final String d;
}

class KCircleShape extends KShape {
  const KCircleShape(this.cx, this.cy, this.r);
  final double cx;
  final double cy;
  final double r;
}

class KRectShape extends KShape {
  const KRectShape(this.x, this.y, this.w, this.h, [this.rx = 0]);
  final double x;
  final double y;
  final double w;
  final double h;
  final double rx;
}

/// A rounded line icon: 24 px grid, round caps and joins. Drawn directly
/// (no SVG loader) so it paints on the first frame, which keeps goldens
/// stable.
@immutable
class KIconData {
  const KIconData(this.shapes);
  final List<KShape> shapes;
}

final _cache = Expando<Path>();

Path _pathOf(KIconData icon) => _cache[icon] ??= _build(icon);

Path _build(KIconData icon) {
  final path = Path();
  for (final shape in icon.shapes) {
    switch (shape) {
      case KPathShape(:final d):
        writeSvgPathDataToPath(d, _PathProxy(path));
      case KCircleShape(:final cx, :final cy, :final r):
        path.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      case KRectShape(:final x, :final y, :final w, :final h, :final rx):
        path.addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w, h),
            Radius.circular(rx),
          ),
        );
    }
  }
  return path;
}

class _PathProxy extends PathProxy {
  _PathProxy(this.path);
  final Path path;

  @override
  void close() => path.close();

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);
}

/// Stroke weight on the 24 grid; larger icons get lighter, as on the Brand
/// board.
double _strokeFor(double size) => switch (size) {
  >= 80 => 1.1,
  >= 56 => 1.3,
  >= 40 => 1.5,
  >= 32 => 1.6,
  _ => 1.8,
};

/// Draws a [KIconData]. Decorative unless [semanticLabel] is given.
class KIcon extends StatelessWidget {
  const KIcon(
    this.icon, {
    super.key,
    this.size = 22,
    this.color,
    this.fill,
    this.strokeWidth,
    this.semanticLabel,
  });

  final KIconData icon;
  final double size;

  /// Defaults to the ambient [IconTheme] colour.
  final Color? color;

  /// Fills the shape too (filled star, active heart).
  final Color? fill;

  /// Stroke in 24-grid units; defaults by size.
  final double? strokeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? IconTheme.of(context).color!;
    final painted = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _KIconPainter(
          _pathOf(icon),
          color,
          fill,
          strokeWidth ?? _strokeFor(size),
        ),
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: painted);
    return Semantics(label: semanticLabel, image: true, child: painted);
  }
}

class _KIconPainter extends CustomPainter {
  _KIconPainter(this.path, this.color, this.fill, this.stroke);

  final Path path;
  final Color color;
  final Color? fill;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    if (fill != null) {
      canvas.drawPath(path, Paint()..color = fill!);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_KIconPainter old) =>
      old.path != path ||
      old.color != color ||
      old.fill != fill ||
      old.stroke != stroke;
}
