import 'package:flutter/widgets.dart';

import '../../../core/ui/k_ui.dart';

/// A product photo in a rounded square, or the package placeholder when
/// there is none or it can't load.
class ProductThumb extends StatelessWidget {
  const ProductThumb({
    super.key,
    required this.url,
    this.size = 44,
    this.semanticLabel,
  });

  final String? url;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    const placeholder = KProductArt(icon: KIcons.package, radius: KRadius.tag);
    return SizedBox.square(
      dimension: size,
      child: url == null
          ? const ExcludeSemantics(child: placeholder)
          : ClipRRect(
              borderRadius: BorderRadius.circular(KRadius.tag),
              child: Image.network(
                url!,
                fit: BoxFit.cover,
                semanticLabel: semanticLabel,
                excludeFromSemantics: semanticLabel == null,
                errorBuilder: (_, _, _) => placeholder,
              ),
            ),
    );
  }
}
