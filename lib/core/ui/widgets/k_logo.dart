import 'package:flutter/material.dart';

import '../theme/k_theme.dart';
import '../theme/k_tokens.dart';

/// The K mark: a rounded bar and a chevron on a 48 grid. Brand sky by
/// default; use [KLogo.white] on sky and [KLogo.onInk] on ink. Never smaller
/// than 20 px.
class KLogo extends StatelessWidget {
  const KLogo({super.key, this.size = 40, this.color})
    : assert(size >= 20, 'The K mark is never smaller than 20 px');

  const KLogo.white({super.key, this.size = 40}) : color = Colors.white;

  const KLogo.onInk({super.key, this.size = 40}) : color = KColors.sky400;

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'K',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _KMarkPainter(color ?? context.k.colors.brand),
        ),
      ),
    );
  }
}

/// The app icon: white mark on a brand-sky tile with 22 % corners.
class KAppIcon extends StatelessWidget {
  const KAppIcon({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.k.colors.brand,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      alignment: Alignment.center,
      child: KLogo.white(size: size * 0.62),
    );
  }
}

class _KMarkPainter extends CustomPainter {
  _KMarkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(10, 9, 7.5, 30),
        const Radius.circular(3.75),
      ),
      Paint()..color = color,
    );
    canvas.drawPath(
      Path()
        ..moveTo(35, 9.5)
        ..lineTo(23.5, 24)
        ..lineTo(35, 38.5),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_KMarkPainter old) => old.color != color;
}
