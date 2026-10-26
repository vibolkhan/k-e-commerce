import 'package:flutter/material.dart';
import 'package:path_parsing/path_parsing.dart';

import '../theme/k_theme.dart';
import '../theme/k_tokens.dart';
import 'k_basics.dart';

enum KSocialProvider { google, apple }

/// "Continue with Google / Apple" in the outline style of S-04, carrying each
/// provider's official mark as their branding guidelines require: the
/// four-colour Google "G" on white and the black Apple logo on white with a
/// black-friendly outline. Label text is passed in so it stays localised.
class KSocialButton extends StatelessWidget {
  const KSocialButton({
    super.key,
    required this.provider,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final KSocialProvider provider;
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final enabled = onPressed != null && !loading;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: Material(
          color: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KRadius.input),
            side: BorderSide(color: c.line2),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (loading)
                    const KSpinner(size: 20, blue: true)
                  else
                    KSocialLogo(provider: provider, size: 20),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: k.text.body.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: enabled ? c.ink : c.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The provider's mark, painted from the official SVG paths.
class KSocialLogo extends StatelessWidget {
  const KSocialLogo({super.key, required this.provider, this.size = 20});

  final KSocialProvider provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _LogoPainter(_marks[provider]!)),
      ),
    );
  }
}

typedef _Mark = ({double grid, List<(Color, String)> parts});

// Google "G" (48 grid) and Apple logo (24 grid).
final Map<KSocialProvider, _Mark> _marks = {
  KSocialProvider.google: (
    grid: 48,
    parts: const [
      (
        Color(0xFFEA4335),
        'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 '
            '14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z',
      ),
      (
        Color(0xFF4285F4),
        'M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 '
            '5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z',
      ),
      (
        Color(0xFFFBBC05),
        'M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19'
            'C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z',
      ),
      (
        Color(0xFF34A853),
        'M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 '
            '2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z',
      ),
    ],
  ),
  KSocialProvider.apple: (
    grid: 24,
    parts: const [
      (
        Color(0xFF000000),
        'M16.37 1.43c0 1.14-.49 2.27-1.18 3.08-.74.9-1.99 1.57-2.99 1.57-.12 '
            '0-.23-.02-.3-.03-.01-.06-.04-.22-.04-.39 0-1.15.57-2.27 1.21-2.98.8-.94 '
            '2.14-1.64 3.25-1.68.03.13.05.28.05.43zm4.56 15.71c-.03.07-.46 1.58-1.52 '
            '3.12-.94 1.34-1.94 2.71-3.43 2.71-1.52 0-1.9-.88-3.63-.88-1.7 0-2.3.91-3.67'
            '.91-1.38 0-2.33-1.26-3.43-2.8-1.29-1.82-2.32-4.63-2.32-7.28 0-4.28 2.8-6.55 '
            '5.55-6.55 1.45 0 2.68.95 3.6.95.87 0 2.22-1.01 3.9-1.01.61 0 2.89.06 4.37 '
            '2.19-.13.09-2.38 1.37-2.38 4.19 0 3.26 2.85 4.42 2.96 4.45z',
      ),
    ],
  ),
};

final _cache = <String, Path>{};

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.mark);
  final _Mark mark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / mark.grid);
    for (final (color, d) in mark.parts) {
      final path = _cache.putIfAbsent(d, () {
        final p = Path();
        writeSvgPathDataToPath(d, _Proxy(p));
        return p;
      });
      canvas.drawPath(path, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.mark != mark;
}

class _Proxy extends PathProxy {
  _Proxy(this.path);
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
