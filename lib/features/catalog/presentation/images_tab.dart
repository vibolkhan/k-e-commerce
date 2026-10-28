import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/k_ui.dart';
import '../data/catalog_repository.dart';
import '../data/file_pick.dart';
import '../domain/product_draft.dart';
import 'editor_widgets.dart';
import 'product_thumb.dart';

/// A-05c Images: upload to the product-images bucket, order (the first is
/// the main image), tie a photo to a variant, and a required description
/// for screen readers.
class ImagesTab extends ConsumerStatefulWidget {
  const ImagesTab({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.issues,
    required this.readOnly,
    required this.uploadFolder,
  });

  final ProductDraft draft;
  final ValueChanged<ProductDraft> onChanged;
  final List<FieldIssue> issues;
  final bool readOnly;

  /// Where new photos go: the product id, or a random folder for a new one.
  final String uploadFolder;

  @override
  ConsumerState<ImagesTab> createState() => _ImagesTabState();
}

class _ImagesTabState extends ConsumerState<ImagesTab> {
  var _uploading = 0;

  ProductDraft get draft => widget.draft;
  List<ImageDraft> get images => draft.images;

  void _setImages(List<ImageDraft> next) =>
      widget.onChanged(draft.copyWith(images: next));

  void _move(int from, int to) {
    final next = [...images];
    next.insert(to, next.removeAt(from));
    _setImages(next);
  }

  Future<void> _delete(int i) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showKConfirm(
      context,
      title: l10n.catalogDeleteImageTitle,
      message: l10n.catalogDeleteImageBody,
      confirmLabel: l10n.catalogDeleteImage,
      cancelLabel: l10n.uiCancel,
      tone: KConfirmTone.destructive,
      icon: KIcons.delete,
    );
    if (ok) _setImages([...images]..removeAt(i));
  }

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context);
    final files = await ref.read(pickFilesProvider)(
      extensions: const ['jpg', 'jpeg', 'png', 'webp'],
      multiple: true,
    );
    if (!mounted || files.isEmpty) return;
    final room = CatalogLimits.images - images.length;
    if (files.length > room) {
      showKToast(
        context,
        message: l10n.catalogImagesFull,
        tone: KToastTone.bad,
      );
    }
    final repo = ref.read(catalogRepositoryProvider);
    for (final file in files.take(room)) {
      if (imageContentType(file.name) == null) {
        showKToast(
          context,
          message: l10n.catalogImageWrongType(file.name),
          tone: KToastTone.bad,
        );
        continue;
      }
      if (file.bytes.length > CatalogLimits.imageBytes) {
        showKToast(
          context,
          message: l10n.catalogImageTooBig(file.name),
          tone: KToastTone.bad,
        );
        continue;
      }
      setState(() => _uploading++);
      final image = await repo.uploadImage(
        folder: widget.uploadFolder,
        fileName: file.name,
        bytes: file.bytes,
      );
      if (!mounted) return;
      setState(() => _uploading--);
      if (image == null) {
        showKToast(
          context,
          message: l10n.catalogUploadFailed(file.name),
          tone: KToastTone.bad,
          icon: KIcons.error,
        );
      } else {
        _setImages([...widget.draft.images, image]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final ro = widget.readOnly;
    final missing = draft.imagesMissingAlt;

    return EditorColumns(
      main: [
        EditorCard(
          title: l10n.catalogProductImages,
          subtitle: l10n.catalogImagesSub,
          children: [
            if (images.isEmpty)
              KEmptyState(
                icon: KIcons.image,
                title: l10n.catalogImagesEmpty,
                message: l10n.catalogImagesEmptyBody,
                compact: true,
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < images.length; i++)
                    _ImageTile(
                      key: ValueKey(images[i].path),
                      image: images[i],
                      index: i,
                      count: images.length,
                      readOnly: ro,
                      onMove: _move,
                      onDelete: () => _delete(i),
                    ),
                ],
              ),
            if (_uploading > 0)
              Row(
                children: [
                  const KSpinner(),
                  const SizedBox(width: 8),
                  Text(l10n.catalogUploading, style: k.text.small),
                ],
              ),
            if (!ro)
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  KButton.outline(
                    label: l10n.catalogAddImages,
                    icon: KIcons.upload,
                    size: KButtonSize.sm,
                    onPressed: images.length >= CatalogLimits.images
                        ? null
                        : _add,
                  ),
                  Text(
                    l10n.catalogImagesHint(images.length, CatalogLimits.images),
                    style: k.text.caption.copyWith(color: k.colors.muted),
                  ),
                ],
              ),
          ],
        ),
        if (images.isNotEmpty)
          EditorCard(
            title: l10n.catalogImageDescriptions,
            subtitle: l10n.catalogImageDescriptionsSub,
            children: [
              for (var i = 0; i < images.length; i++)
                _AltRow(
                  key: ValueKey('alt-${images[i].path}'),
                  index: i,
                  image: images[i],
                  variants: draft.variants,
                  readOnly: ro,
                  error: issueFor(l10n, widget.issues, 'images.$i.alt'),
                  onChanged: (img) => _setImages([
                    ...images.take(i),
                    img,
                    ...images.skip(i + 1),
                  ]),
                ),
            ],
          ),
      ],
      side: [
        if (missing > 0)
          KBanner(
            message: l10n.catalogAltMissing(missing),
            tone: KBannerTone.warn,
          ),
        EditorCard(
          title: l10n.catalogPhotoGuidelines,
          children: [
            for (final line in [
              l10n.catalogGuideSquare,
              l10n.catalogGuideBackground,
              l10n.catalogGuidePerColour,
              l10n.catalogGuideNoText,
            ])
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KIcon(KIcons.check, size: 18, color: k.colors.ok),
                  const SizedBox(width: 8),
                  Expanded(child: Text(line, style: k.text.small)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({
    super.key,
    required this.image,
    required this.index,
    required this.count,
    required this.readOnly,
    required this.onMove,
    required this.onDelete,
  });

  final ImageDraft image;
  final int index;
  final int count;
  final bool readOnly;
  final void Function(int from, int to) onMove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final main = index == 0;
    return SizedBox(
      width: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: main ? k.colors.primary : k.colors.line,
                    width: main ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(KRadius.box),
                ),
                padding: const EdgeInsets.all(2),
                child: ProductThumb(
                  url: image.url,
                  size: 140,
                  semanticLabel: image.alt.en.isEmpty
                      ? l10n.catalogAltLabel(index + 1)
                      : image.alt.en,
                ),
              ),
              if (main)
                Positioned(
                  left: 8,
                  top: 8,
                  child: KStatusPill(
                    label: l10n.catalogMainImage,
                    tone: KTone.blue,
                  ),
                ),
            ],
          ),
          if (!readOnly)
            Row(
              children: [
                KIconButton(
                  icon: KIcons.back,
                  label: l10n.catalogMoveEarlier,
                  onPressed: index > 0 ? () => onMove(index, index - 1) : null,
                ),
                KIconButton(
                  icon: KIcons.chevronRight,
                  label: l10n.catalogMoveLater,
                  onPressed: index < count - 1
                      ? () => onMove(index, index + 1)
                      : null,
                ),
                const Spacer(),
                KIconButton(
                  icon: KIcons.delete,
                  label: l10n.catalogDeleteImage,
                  color: k.colors.bad,
                  onPressed: onDelete,
                ),
              ],
            ),
          if (!readOnly && !main)
            KButton.ghost(
              label: l10n.catalogSetMain,
              size: KButtonSize.sm,
              onPressed: () => onMove(index, 0),
            ),
        ],
      ),
    );
  }
}

class _AltRow extends StatelessWidget {
  const _AltRow({
    super.key,
    required this.index,
    required this.image,
    required this.variants,
    required this.readOnly,
    required this.error,
    required this.onChanged,
  });

  final int index;
  final ImageDraft image;
  final List<VariantDraft> variants;
  final bool readOnly;
  final String? error;
  final ValueChanged<ImageDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final skus = [
      for (final v in variants)
        if (v.sku.trim().isNotEmpty) v,
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProductThumb(url: image.url, size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KTextField(
                label: l10n.catalogAltLabel(index + 1),
                hint: l10n.catalogAltHint,
                initialValue: image.alt.en,
                readOnly: readOnly,
                maxLength: CatalogLimits.alt,
                errorText: error,
                onChanged: (v) =>
                    onChanged(image.copyWith(alt: image.alt.copyWith(en: v))),
              ),
              const SizedBox(height: 8),
              KTextField(
                hint: l10n.catalogAltKmHint,
                initialValue: image.alt.km,
                readOnly: readOnly,
                maxLength: CatalogLimits.alt,
                onChanged: (v) =>
                    onChanged(image.copyWith(alt: image.alt.copyWith(km: v))),
              ),
              if (skus.length > 1) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l10n.catalogImageVariant,
                      style: k.text.small.copyWith(color: k.colors.muted),
                    ),
                    KChip(
                      label: l10n.catalogAllVariants,
                      selected: image.variantSku == null,
                      onTap: readOnly
                          ? null
                          : () => onChanged(
                              image.copyWith(variantSku: () => null),
                            ),
                    ),
                    for (final v in skus)
                      KChip(
                        label: v.label(),
                        selected: image.variantSku == v.sku.trim(),
                        onTap: readOnly
                            ? null
                            : () => onChanged(
                                image.copyWith(variantSku: () => v.sku.trim()),
                              ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
