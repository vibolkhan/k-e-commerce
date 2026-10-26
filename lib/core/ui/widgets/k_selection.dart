import 'package:flutter/material.dart';

import '../icons/k_icon.dart';
import '../theme/k_theme.dart';
import '../theme/k_tokens.dart';

/// 36 px filter / choice pill with an optional count.
class KChip extends StatelessWidget {
  const KChip({
    super.key,
    required this.label,
    this.selected = false,
    this.count,
    this.icon,
    this.onTap,
  });

  final String label;
  final bool selected;
  final int? count;
  final KIconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final fg = selected ? c.primaryInk : c.ink2;
    return Semantics(
      button: true,
      selected: selected,
      label: count == null ? label : '$label, $count',
      excludeSemantics: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinTap),
        child: Center(
          widthFactor: 1,
          child: Material(
            color: selected ? c.tint2 : c.surface,
            shape: StadiumBorder(
              side: BorderSide(color: selected ? c.tintLine : c.line2),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      KIcon(icon!, size: 16, color: fg),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      style: k.text.label.copyWith(height: 1, color: fg),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: c.primary,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$count',
                          style: k.text.caption.copyWith(
                            fontSize: 11,
                            height: 1,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class KSegment<T> {
  const KSegment(this.value, this.label);
  final T value;
  final String label;
}

/// Segmented control: soft track, white selected segment, 44 px tall.
class KSegmented<T> extends StatelessWidget {
  const KSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<KSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.soft,
        borderRadius: BorderRadius.circular(KRadius.box),
      ),
      child: Row(
        children: [
          for (final (i, s) in segments.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                button: true,
                inMutuallyExclusiveGroup: true,
                selected: s.value == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(s.value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: s.value == selected
                          ? Colors.white
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: s.value == selected ? k.shadow1 : null,
                    ),
                    child: Text(
                      s.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: k.text.button.copyWith(
                        fontSize: 14,
                        color: s.value == selected ? c.ink : c.ink3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class KTab {
  const KTab(this.label, {this.count});
  final String label;
  final int? count;
}

/// Underlined tabs with optional counts. [fill] splits the width evenly;
/// otherwise tabs scroll horizontally.
class KTabs extends StatelessWidget {
  const KTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
    this.fill = false,
  });

  final List<KTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;

    Widget tab(int i) {
      final t = tabs[i];
      final on = i == selectedIndex;
      return Semantics(
        selected: on,
        button: true,
        label: t.count == null ? t.label : '${t.label}, ${t.count}',
        excludeSemantics: true,
        onTap: () => onChanged(i),
        child: InkWell(
          onTap: () => onChanged(i),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            foregroundDecoration: on
                ? _Underline(c.primary)
                : const BoxDecoration(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  t.label,
                  style: k.text.button.copyWith(
                    color: on ? c.primary : c.muted,
                  ),
                ),
                if (t.count != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: on ? c.tint2 : c.soft,
                      borderRadius: BorderRadius.circular(KRadius.pill),
                    ),
                    child: Text(
                      '${t.count}',
                      style: k.text.caption.copyWith(
                        fontSize: 11,
                        height: 14 / 11,
                        fontWeight: FontWeight.w800,
                        color: on ? c.primaryInk : c.ink3,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final row = Row(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      children: [
        for (var i = 0; i < tabs.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          fill ? Expanded(child: tab(i)) : tab(i),
        ],
      ],
    );
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: fill
          ? row
          : SingleChildScrollView(scrollDirection: Axis.horizontal, child: row),
    );
  }
}

/// 3 px rounded bar at the bottom of the active tab, inset 12 px.
class _Underline extends Decoration {
  const _Underline(this.color);
  final Color color;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _UnderlinePainter(color);
}

class _UnderlinePainter extends BoxPainter {
  _UnderlinePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration config) {
    final size = config.size!;
    final rect = Rect.fromLTRB(
      offset.dx + 12,
      offset.dy + size.height - 3,
      offset.dx + size.width - 12,
      offset.dy + size.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        rect,
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      ),
      Paint()..color = color,
    );
  }
}

/// Radio card for choices like payment method.
class KOptionTile extends StatelessWidget {
  const KOptionTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final KIconData? icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: enabled,
      child: Material(
        color: !enabled
            ? c.soft
            : selected
            ? c.tint
            : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KRadius.box),
          side: BorderSide(
            color: selected ? c.primary : c.line,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: selected ? 15 : 16,
                vertical: selected ? 13 : 14,
              ),
              child: Row(
                children: [
                  _RadioDot(selected: selected),
                  const SizedBox(width: 12),
                  if (icon != null) ...[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c.tint2,
                        borderRadius: BorderRadius.circular(KRadius.input),
                      ),
                      alignment: Alignment.center,
                      child: KIcon(icon!, color: c.primaryInk),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: k.text.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: k.text.small.copyWith(color: c.muted),
                          ),
                      ],
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

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.surface,
        border: Border.all(
          color: selected ? c.primary : c.line2,
          width: selected ? 6 : 1.5,
        ),
      ),
    );
  }
}

/// Labelled switch row (44 px min).
class KSwitchRow extends StatelessWidget {
  const KSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinTap),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: k.text.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
