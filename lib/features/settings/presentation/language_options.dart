import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/supported_languages.dart';
import '../../../core/ui/k_ui.dart';

/// [cards]: big glyph cards for first launch (S-02). [list]: one bordered
/// list for the Account language sheet (S-08c).
enum LanguageOptionsStyle { cards, list }

/// Radio group of the app languages. Each row shows the name in the UI
/// language plus the native name, so it reads in either language; in the
/// list style the language in use is labelled "Current language" instead.
class LanguageOptions extends StatelessWidget {
  const LanguageOptions({
    super.key,
    required this.selected,
    required this.onChanged,
    this.current,
    this.style = LanguageOptionsStyle.list,
  });

  final Locale selected;
  final ValueChanged<Locale> onChanged;

  /// The language the app is in now (list style only).
  final Locale? current;
  final LanguageOptionsStyle style;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final rows = [
      for (final language in appLanguages)
        _LanguageRow(
          language: language,
          title: language.name(l10n),
          subtitle:
              style == LanguageOptionsStyle.list &&
                  language.code == current?.languageCode
              ? l10n.languageCurrent
              : language.nativeName,
          selected: language.code == selected.languageCode,
          style: style,
          onTap: () => onChanged(language.locale),
        ),
    ];
    return Semantics(
      label: l10n.languageAppLanguage,
      container: true,
      explicitChildNodes: true,
      child: switch (style) {
        LanguageOptionsStyle.cards => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, row) in rows.indexed) ...[
              if (i > 0) const SizedBox(height: KSpacing.x3),
              row,
            ],
          ],
        ),
        LanguageOptionsStyle.list => Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(KRadius.box),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, row) in rows.indexed) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: c.line),
                row,
              ],
            ],
          ),
        ),
      },
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.language,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.style,
    required this.onTap,
  });

  final AppLanguage language;
  final String title;
  final String subtitle;
  final bool selected;
  final LanguageOptionsStyle style;
  final VoidCallback onTap;

  bool get _cards => style == LanguageOptionsStyle.cards;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: k.text.body.copyWith(
            fontSize: _cards ? 16 : 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != title)
          Text(
            subtitle,
            style: (_cards ? k.text.body : k.text.small).copyWith(
              color: c.muted,
            ),
          ),
      ],
    );
    final row = Row(
      children: [
        if (_cards) ...[
          _Glyph(code: language.code, selected: selected),
          const SizedBox(width: 14),
        ],
        Expanded(child: text),
        const SizedBox(width: KSpacing.x3),
        KRadioMark(selected: selected),
      ],
    );
    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: _cards ? 80 : 64),
      child: Padding(
        padding: _cards
            ? EdgeInsets.symmetric(
                horizontal: selected ? 17 : 18,
                vertical: selected ? 15 : 16,
              )
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: row,
      ),
    );
    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        button: true,
        child: _cards
            ? Material(
                color: selected ? c.tint : c.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(KRadius.box),
                  side: BorderSide(
                    color: selected ? c.primary : c.line,
                    width: selected ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(onTap: onTap, child: content),
              )
            : Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: onTap, child: content),
              ),
      ),
    );
  }
}

/// The letter badge on the S-02 cards: "ក" for Khmer, "A" for English.
class _Glyph extends StatelessWidget {
  const _Glyph({required this.code, required this.selected});

  final String code;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final khmer = code == 'km';
    return ExcludeSemantics(
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.surface : c.tint2,
          borderRadius: BorderRadius.circular(KRadius.box),
        ),
        child: Text(
          khmer ? 'ក' : 'A',
          style: k.text.body.copyWith(
            fontFamily: khmer ? KFonts.khmer : null,
            fontSize: khmer ? 22 : 18,
            height: 1.2,
            fontWeight: khmer ? FontWeight.w600 : FontWeight.w800,
            color: c.primaryInk,
          ),
        ),
      ),
    );
  }
}
