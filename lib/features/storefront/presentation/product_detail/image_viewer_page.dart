import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/ui/k_ui.dart';
import '../../domain/product_detail.dart';
import '../store_widgets.dart';
import '../storefront_providers.dart';
import 'product_detail_providers.dart';

/// C-05e: the product's photos full screen on ink, with pinch to zoom and a
/// thumbnail strip. Opens on photo [initialIndex].
class ImageViewerPage extends ConsumerStatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.productId,
    this.initialIndex = 0,
    this.shareUrl,
  });

  final String productId;
  final int initialIndex;

  /// The product link for Share; copied to the clipboard.
  final String? shareUrl;

  @override
  ConsumerState<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends ConsumerState<ImageViewerPage> {
  late int _index = widget.initialIndex;
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int i) {
    setState(() => _index = i);
    _pages.animateToPage(
      i,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final product = ref
        .watch(
          productDetailProvider((
            id: widget.productId,
            viewer: watchViewer(ref),
          )),
        )
        .value;
    final lang = Localizations.localeOf(context).languageCode;
    final slides = product == null ? 1 : pdSlideCount(product);
    final index = _index.clamp(0, slides - 1);

    Widget slide(int i) {
      if (product == null) return const SizedBox.shrink();
      final art = productArtFor(product.id, product.name.en);
      if (product.images.isEmpty) return art;
      final image = product.images[i];
      final alt = image.alt.of(lang);
      return KNetworkImage(
        url: image.url,
        fit: BoxFit.contain,
        semanticLabel: alt.isEmpty ? product.name.of(lang) : alt,
        fallback: art,
      );
    }

    return Theme(
      data: Theme.of(context).copyWith(scaffoldBackgroundColor: KColors.ink),
      child: Scaffold(
        key: const Key('pd-viewer'),
        body: Semantics(
          explicitChildNodes: true,
          scopesRoute: true,
          namesRoute: true,
          label: l10n.pdViewerA11y(index + 1, slides),
          child: SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      const SizedBox(width: 4),
                      KIconButton(
                        icon: KIcons.close,
                        label: l10n.pdCloseViewer,
                        color: Colors.white,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            l10n.pdPhotoCounter(index + 1, slides),
                            textAlign: TextAlign.center,
                            style: context.k.text.body.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      KIconButton(
                        icon: KIcons.share,
                        label: l10n.pdSharePhoto,
                        color: Colors.white,
                        onPressed: widget.shareUrl == null
                            ? null
                            : () => copyProductLink(context, widget.shareUrl!),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: slides,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (_, i) => InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Center(child: slide(i)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const KIcon(
                        KIcons.zoomIn,
                        size: 16,
                        color: KColors.line2,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.pdPinchZoom,
                        style: context.k.text.small.copyWith(
                          color: KColors.line2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (slides > 1)
                  SizedBox(
                    height: 100,
                    child: Center(
                      child: ListView.separated(
                        shrinkWrap: true,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        itemCount: slides,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => Semantics(
                          button: true,
                          selected: i == index,
                          label: l10n.pdPhotoN(i + 1),
                          excludeSemantics: true,
                          onTap: () => _go(i),
                          child: GestureDetector(
                            key: ValueKey('pd-thumb-$i'),
                            onTap: () => _go(i),
                            child: Container(
                              width: 56,
                              height: 56,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  KRadius.input,
                                ),
                                border: Border.all(
                                  color: i == index
                                      ? KColors.sky400
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: slide(i),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Photos in the gallery; one placeholder slide when there are none.
int pdSlideCount(ProductDetail product) =>
    product.images.isEmpty ? 1 : product.images.length;

/// Share without a share sheet: the link goes on the clipboard.
Future<void> copyProductLink(BuildContext context, String url) async {
  final l10n = AppLocalizations.of(context);
  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  showKToast(context, message: l10n.pdLinkCopied, tone: KToastTone.info);
}
