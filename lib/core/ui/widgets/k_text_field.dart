import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/generated/app_localizations.dart';
import '../icons/k_icon.dart';
import '../icons/k_icons.dart';
import '../theme/k_theme.dart';
import '../theme/k_tokens.dart';

/// Labelled text input: 48 px box, 3 px focus ring, inline error with icon,
/// help text, optional prefix segment (`+855`) or prefix icon.
class KTextField extends StatefulWidget {
  const KTextField({
    super.key,
    this.label,
    this.optional = false,
    this.controller,
    this.initialValue,
    this.focusNode,
    this.hint,
    this.prefixText,
    this.prefixIcon,
    this.suffix,
    this.errorText,
    this.helpText,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
  }) : _search = false;

  /// Soft, borderless 44 px search box with a search icon.
  const KTextField.search({
    super.key,
    required String this.hint,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.readOnly = false,
    this.suffix,
  }) : _search = true,
       label = null,
       optional = false,
       initialValue = null,
       prefixText = null,
       prefixIcon = KIcons.search,
       errorText = null,
       helpText = null,
       enabled = true,
       obscureText = false,
       keyboardType = TextInputType.text,
       textInputAction = TextInputAction.search,
       autofillHints = null,
       inputFormatters = null,
       maxLines = 1,
       maxLength = null;

  final String? label;

  /// Adds "(optional)" after the label.
  final bool optional;
  final TextEditingController? controller;
  final String? initialValue;
  final FocusNode? focusNode;
  final String? hint;

  /// Fixed text before the input with a divider, e.g. `+855`.
  final String? prefixText;
  final KIconData? prefixIcon;
  final Widget? suffix;

  /// Replaces [helpText] and turns the box red.
  final String? errorText;
  final String? helpText;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;

  /// More than 1 makes a 96 px min-height text area.
  final int maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool _search;

  @override
  State<KTextField> createState() => _KTextFieldState();
}

class _KTextFieldState extends State<KTextField> {
  FocusNode? _ownFocus;
  TextEditingController? _ownController;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());
  TextEditingController get _controller =>
      widget.controller ??
      (_ownController ??= TextEditingController(text: widget.initialValue));

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(KTextField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
  }

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _ownFocus?.dispose();
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final hasError = widget.errorText != null;
    final focused = _focus.hasFocus;
    final multiline = widget.maxLines > 1;
    final search = widget._search;

    final borderColor = search
        ? Colors.transparent
        : hasError
        ? c.bad
        : focused
        ? c.primary
        : c.line2;
    final ring = search
        ? null
        : hasError
        ? c.badBg
        : focused
        ? c.tint2
        : null;
    final fill = search
        ? c.soft
        : widget.enabled
        ? c.surface
        : c.soft;
    final textStyle = k.text.body.copyWith(
      color: widget.enabled ? c.ink : c.ink3,
    );

    final field = TextField(
      controller: _controller,
      focusNode: _focus,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      obscureText: widget.obscureText,
      keyboardType:
          widget.keyboardType ??
          (multiline ? TextInputType.multiline : TextInputType.text),
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      inputFormatters: widget.inputFormatters,
      maxLines: widget.maxLines,
      minLines: multiline ? 3 : 1,
      maxLength: widget.maxLength,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onTap: widget.onTap,
      style: textStyle,
      cursorColor: c.primary,
      decoration: InputDecoration(
        isCollapsed: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        counterText: '',
        hintText: widget.hint,
        hintStyle: textStyle.copyWith(color: search ? c.ink3 : c.muted),
      ),
    );

    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      constraints: BoxConstraints(minHeight: multiline ? 96 : 0),
      height: multiline ? null : (search ? 44 : 48),
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: multiline ? 12 : 0,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(KRadius.input),
        border: Border.all(color: borderColor),
        boxShadow: ring == null
            ? null
            : [BoxShadow(color: ring, spreadRadius: 3)],
      ),
      child: Row(
        crossAxisAlignment: multiline
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          if (widget.prefixIcon != null) ...[
            KIcon(
              widget.prefixIcon!,
              size: 20,
              color: search ? c.ink3 : c.muted,
            ),
            const SizedBox(width: 10),
          ],
          if (widget.prefixText != null) ...[
            Container(
              height: 24,
              padding: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: c.line)),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.prefixText!,
                style: k.text.body.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(child: field),
          if (widget.suffix != null) ...[
            const SizedBox(width: 10),
            IconTheme(
              data: IconThemeData(color: c.muted),
              child: widget.suffix!,
            ),
          ],
        ],
      ),
    );

    if (search) return box;

    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.label != null) ...[
            Text.rich(
              TextSpan(
                text: widget.label,
                children: [
                  if (widget.optional)
                    TextSpan(
                      text: ' ${l10n.uiOptional}',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: c.muted,
                      ),
                    ),
                ],
              ),
              style: k.text.label,
            ),
            const SizedBox(height: 6),
          ],
          box,
          if (hasError) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KIcon(KIcons.alert, size: 16, color: c.bad),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.errorText!,
                    style: k.text.caption.copyWith(
                      color: c.bad,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (widget.helpText != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.helpText!,
              style: k.text.caption.copyWith(
                color: c.muted,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One-time code entry: [length] boxes 48×56 over a single hidden field, so
/// paste and SMS autofill work.
class KOtpField extends StatefulWidget {
  const KOtpField({
    super.key,
    this.length = 6,
    this.controller,
    this.focusNode,
    this.error = false,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
    this.onCompleted,
  });

  final int length;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Red boxes after a wrong code.
  final bool error;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;

  @override
  State<KOtpField> createState() => _KOtpFieldState();
}

class _KOtpFieldState extends State<KOtpField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  late final FocusNode _focus = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_rebuild);
    _focus.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_rebuild);
    _focus.removeListener(_rebuild);
    if (widget.controller == null) _controller.dispose();
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  void _changed(String value) {
    widget.onChanged?.call(value);
    if (value.length == widget.length) widget.onCompleted?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final text = _controller.text;
    final active = _focus.hasFocus
        ? text.length.clamp(0, widget.length - 1)
        : -1;

    Widget cell(int i) {
      final char = i < text.length ? text[i] : '';
      final isActive = i == active && !widget.error;
      return Container(
        width: 48,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.error ? c.badBg : c.surface,
          borderRadius: BorderRadius.circular(KRadius.input),
          border: Border.all(
            color: widget.error
                ? c.bad
                : isActive
                ? c.primary
                : c.line2,
          ),
          boxShadow: isActive
              ? [BoxShadow(color: c.tint2, spreadRadius: 3)]
              : null,
        ),
        child: Text(
          char,
          style: k.text.h2.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: widget.error ? c.bad : c.ink,
          ),
        ),
      );
    }

    return Semantics(
      label: l10n.uiOtpGroup(widget.length),
      child: Stack(
        children: [
          ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [for (var i = 0; i < widget.length; i++) cell(i)],
            ),
          ),
          Positioned.fill(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(widget.length),
              ],
              onChanged: _changed,
              showCursor: false,
              style: const TextStyle(color: Colors.transparent, fontSize: 1),
              cursorColor: Colors.transparent,
              decoration: const InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                counterText: '',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
