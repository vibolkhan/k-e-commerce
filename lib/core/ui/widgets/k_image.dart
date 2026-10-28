import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/k_theme.dart';

/// A remote picture (product photo, banner), cached on disk on phones and by
/// the browser on the web. Shows a skeleton tint while loading and
/// [fallback] when there is no [url] or it fails to load.
class KNetworkImage extends StatelessWidget {
  const KNetworkImage({
    super.key,
    required this.url,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.semanticLabel,
  });

  final String? url;
  final Widget fallback;
  final BoxFit fit;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final src = url;
    if (src == null || src.isEmpty) return fallback;
    return Semantics(
      image: semanticLabel != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, box) {
          final ratio = MediaQuery.devicePixelRatioOf(context);
          // Decode at the size shown, not the uploaded size.
          final width = box.maxWidth.isFinite
              ? (box.maxWidth * ratio).round()
              : null;
          return CachedNetworkImage(
            imageUrl: src,
            fit: fit,
            width: box.maxWidth.isFinite ? box.maxWidth : null,
            height: box.maxHeight.isFinite ? box.maxHeight : null,
            memCacheWidth: width,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (context, _) =>
                ColoredBox(color: context.k.colors.skeleton),
            errorWidget: (_, _, _) => fallback,
          );
        },
      ),
    );
  }
}
