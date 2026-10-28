import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/ui/k_ui.dart';
import '../../admin/presentation/admin_shell.dart';
import '../data/catalog_repository.dart';
import '../data/file_pick.dart';
import '../domain/csv_import.dart';
import 'catalog_labels.dart';
import 'catalog_providers.dart';

/// A-05d: a wide modal over the product list on desktop, its own page on
/// phones.
Future<void> openImportWizard(BuildContext context) async {
  if (!isAdminWide(context)) {
    context.go(AppRoutes.adminCatalogImport);
    return;
  }
  await showDialog<void>(
    context: context,
    barrierColor: KColors.scrim,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Container(
          decoration: BoxDecoration(
            color: dialogContext.k.colors.surface,
            borderRadius: BorderRadius.circular(KRadius.dialog),
          ),
          clipBehavior: Clip.antiAlias,
          child: ImportWizard(onClose: () => Navigator.of(dialogContext).pop()),
        ),
      ),
    ),
  );
}

/// The phone route (`/admin/catalog/import`).
class ImportWizardPage extends StatelessWidget {
  const ImportWizardPage({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.k.colors.surface,
    child: SafeArea(
      child: ImportWizard(onClose: () => context.go(AppRoutes.adminCatalog)),
    ),
  );
}

enum _Step { upload, match, review }

class ImportWizard extends ConsumerStatefulWidget {
  const ImportWizard({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<ImportWizard> createState() => _ImportWizardState();
}

class _ImportWizardState extends ConsumerState<ImportWizard> {
  var _step = _Step.upload;
  String? _fileName;
  String _csv = '';
  CsvHead? _head;
  var _mapping = <String, ImportField>{};
  ImportPreview? _preview;
  String? _error;
  var _busy = false;

  Future<void> _choose() async {
    final l10n = AppLocalizations.of(context);
    final files = await ref.read(pickFilesProvider)(extensions: const ['csv']);
    if (!mounted || files.isEmpty) return;
    final file = files.first;
    if (file.bytes.length > maxImportBytes) {
      setState(() => _error = l10n.catalogImpTooLarge);
      return;
    }
    final text = utf8.decode(file.bytes, allowMalformed: true);
    final head = CsvHead.parse(text);
    if (head == null || head.rowCount == 0) {
      setState(() => _error = l10n.catalogImpEmpty);
      return;
    }
    setState(() {
      _fileName = file.name;
      _csv = text;
      _head = head;
      _mapping = autoMapping(head.header);
      _preview = null;
      _error = null;
      _step = _Step.match;
    });
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await ref
        .read(catalogRepositoryProvider)
        .previewImport(_csv, _mapping);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      switch (outcome) {
        case ImportPreview():
          _preview = outcome;
          _step = _Step.review;
        case ImportRefused(:final reason):
          _error = importRefusalMessage(l10n, reason);
        case ImportDone():
          _error = l10n.catalogErrUnknown;
      }
    });
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await ref
        .read(catalogRepositoryProvider)
        .commitImport(_csv, _mapping);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (outcome case ImportDone(:final products) when products > 0) {
      ref.invalidate(catalogPageProvider);
      showKToast(context, message: l10n.catalogImported(products));
      widget.onClose();
      return;
    }
    setState(() {
      _busy = false;
      _error = switch (outcome) {
        ImportRefused(:final reason) => importRefusalMessage(l10n, reason),
        _ => l10n.catalogImportNothing,
      };
    });
  }

  Future<void> _copyReport() async {
    final l10n = AppLocalizations.of(context);
    final errors = _preview?.errors ?? const [];
    await Clipboard.setData(
      ClipboardData(
        text: [for (final e in errors) importRowMessage(l10n, e)].join('\n'),
      ),
    );
    if (mounted) showKToast(context, message: l10n.catalogImportReportCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final missing = missingFields(_mapping);

    final body = switch (_step) {
      _Step.upload => _UploadStep(onChoose: _choose),
      _Step.match => _MatchStep(
        fileName: _fileName!,
        head: _head!,
        mapping: _mapping,
        missing: missing,
        onReplace: _choose,
        onMap: (column, field) => setState(() {
          _mapping = {
            for (final e in _mapping.entries)
              // A field maps to one column: the old column lets it go.
              e.key: e.key == column
                  ? field
                  : (e.value == field && field != ImportField.ignore
                        ? ImportField.ignore
                        : e.value),
          };
          _preview = null;
        }),
      ),
      _Step.review => _ReviewStep(preview: _preview!),
    };

    final footer = <Widget>[
      if (_step == _Step.review && (_preview?.errors.isNotEmpty ?? false))
        KButton.ghost(
          label: l10n.catalogImportErrorReport,
          icon: KIcons.invoice,
          onPressed: _copyReport,
        ),
      if (_step != _Step.upload)
        KButton.outline(
          label: l10n.catalogImportBack,
          onPressed: _busy
              ? null
              : () => setState(() {
                  _error = null;
                  _step = _Step.values[_step.index - 1];
                }),
        ),
      if (_step == _Step.match)
        KButton(
          label: l10n.catalogImportCheck,
          loading: _busy,
          onPressed: _busy || missing.isNotEmpty ? null : _check,
        ),
      if (_step == _Step.review)
        KButton(
          label: l10n.catalogImportContinue(_preview!.valid),
          loading: _busy,
          onPressed: _busy || _preview!.valid == 0 ? null : _import,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(l10n.catalogImportTitle, style: k.text.h3),
                ),
              ),
              KIconButton(
                icon: KIcons.close,
                label: MaterialLocalizations.of(context).closeButtonLabel,
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _Stepper(step: _step),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            children: [
              if (_error != null) ...[
                KBanner(message: _error!, tone: KBannerTone.bad),
                const SizedBox(height: 16),
              ],
              body,
            ],
          ),
        ),
        if (footer.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: k.colors.line)),
            ),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 8,
              children: footer,
            ),
          ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final labels = [
      l10n.catalogStepUpload,
      l10n.catalogStepMatch,
      l10n.catalogStepReview,
    ];
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        for (var i = 0; i < labels.length; i++)
          Semantics(
            selected: i == step.index,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < step.index
                        ? k.colors.ok
                        : i == step.index
                        ? k.colors.primary
                        : k.colors.soft,
                  ),
                  child: Center(
                    child: i < step.index
                        ? const KIcon(
                            KIcons.check,
                            size: 14,
                            color: Colors.white,
                          )
                        : Text(
                            '${i + 1}',
                            style: k.text.caption.copyWith(
                              color: i == step.index
                                  ? Colors.white
                                  : k.colors.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  labels[i],
                  style: k.text.small.copyWith(
                    fontWeight: i == step.index ? FontWeight.w700 : null,
                    color: i == step.index ? k.colors.ink : k.colors.muted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _UploadStep extends StatelessWidget {
  const _UploadStep({required this.onChoose});

  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: k.colors.soft,
        border: Border.all(color: k.colors.line2),
        borderRadius: BorderRadius.circular(KRadius.card),
      ),
      child: Column(
        children: [
          KIcon(KIcons.upload, size: 32, color: k.colors.primary),
          const SizedBox(height: 12),
          Text(
            l10n.catalogImportUploadBody,
            textAlign: TextAlign.center,
            style: k.text.small.copyWith(color: k.colors.ink2),
          ),
          const SizedBox(height: 16),
          KButton(label: l10n.catalogImportChoose, onPressed: onChoose),
        ],
      ),
    );
  }
}

class _MatchStep extends StatelessWidget {
  const _MatchStep({
    required this.fileName,
    required this.head,
    required this.mapping,
    required this.missing,
    required this.onReplace,
    required this.onMap,
  });

  final String fileName;
  final CsvHead head;
  final Map<String, ImportField> mapping;
  final List<ImportField> missing;
  final VoidCallback onReplace;
  final void Function(String column, ImportField field) onMap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final headStyle = k.text.caption.copyWith(
      color: k.colors.muted,
      fontWeight: FontWeight.w700,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: k.colors.line),
            borderRadius: BorderRadius.circular(KRadius.input),
          ),
          child: Row(
            children: [
              KIcon(KIcons.invoice, color: k.colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: k.text.label.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      l10n.catalogImportFileMeta(
                        head.rowCount,
                        head.header.length,
                      ),
                      style: k.text.caption.copyWith(color: k.colors.muted),
                    ),
                  ],
                ),
              ),
              KButton.ghost(
                label: l10n.catalogReplaceFile,
                size: KButtonSize.sm,
                onPressed: onReplace,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (missing.isNotEmpty) ...[
          KBanner(
            message: l10n.catalogImportMissing(
              missing.map((f) => importFieldLabel(l10n, f)).join(', '),
            ),
            tone: KBannerTone.warn,
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(child: Text(l10n.catalogColumnInFile, style: headStyle)),
            if (isAdminWide(context))
              Expanded(child: Text(l10n.catalogExampleValue, style: headStyle)),
            Expanded(child: Text(l10n.catalogImportAs, style: headStyle)),
          ],
        ),
        for (var i = 0; i < head.header.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: k.colors.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    head.header[i],
                    style: k.text.small.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (isAdminWide(context))
                  Expanded(
                    child: Text(
                      head.sample[i].isEmpty
                          ? l10n.catalogEmptyInRows(head.emptyCounts[i])
                          : head.sample[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: k.text.small.copyWith(
                        color: head.sample[i].isEmpty ? k.colors.muted : null,
                      ),
                    ),
                  ),
                Expanded(
                  child: DropdownButton<ImportField>(
                    isExpanded: true,
                    value: mapping[head.header[i]] ?? ImportField.ignore,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final field in ImportField.values)
                        DropdownMenuItem(
                          value: field,
                          child: Text(
                            importFieldLabel(l10n, field),
                            style: k.text.small,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (f) =>
                        onMap(head.header[i], f ?? ImportField.ignore),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({required this.preview});

  final ImportPreview preview;

  /// The list stays readable; the full list is in the error report.
  static const shownErrors = 50;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final errors = preview.errors;
    final badRows = {for (final e in errors) e.row}.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (badRows > 0)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: k.colors.badBg,
              borderRadius: BorderRadius.circular(KRadius.input),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.catalogImportErrorsTitle(badRows),
                  style: k.text.label.copyWith(
                    color: k.colors.bad,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                for (final e in errors.take(shownErrors))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(importRowMessage(l10n, e), style: k.text.small),
                  ),
                if (errors.length > shownErrors) Text('…', style: k.text.small),
              ],
            ),
          )
        else
          KBanner(
            message: l10n.catalogImportAllGood(preview.valid),
            tone: KBannerTone.ok,
          ),
        const SizedBox(height: 12),
        if (preview.valid > 0)
          Text(
            l10n.catalogImportProducts(preview.products),
            style: k.text.small.copyWith(color: k.colors.ink2),
          ),
      ],
    );
  }
}
