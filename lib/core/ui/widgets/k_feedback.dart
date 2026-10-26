import 'package:flutter/material.dart';

import '../icons/k_icon.dart';
import '../icons/k_icons.dart';
import '../theme/k_theme.dart';
import '../theme/k_tokens.dart';

enum KStepState { done, now, todo, bad }

class KTimelineStep {
  const KTimelineStep({
    required this.title,
    required this.state,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final KStepState state;

  /// Icon in the "now" dot; defaults to a parcel.
  final KIconData? icon;
}

/// Vertical status timeline (order tracking, returns, RFQs).
class KTimeline extends StatelessWidget {
  const KTimeline({super.key, required this.steps});
  final List<KTimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, s) in steps.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 28,
                  child: Column(
                    children: [
                      _Dot(step: s),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.only(top: 2, bottom: 2),
                            decoration: BoxDecoration(
                              color: s.state == KStepState.done
                                  ? c.primary
                                  : c.line,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: 4,
                      bottom: i < steps.length - 1 ? 18 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title,
                          style: k.text.small.copyWith(
                            fontSize: 14,
                            height: 20 / 14,
                            fontWeight: s.state == KStepState.todo
                                ? FontWeight.w600
                                : FontWeight.w700,
                            color: s.state == KStepState.todo ? c.muted : c.ink,
                          ),
                        ),
                        if (s.subtitle != null)
                          Text(
                            s.subtitle!,
                            style: k.text.caption.copyWith(
                              height: 17 / 12,
                              fontWeight: FontWeight.w400,
                              color: c.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.step});
  final KTimelineStep step;

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    final (bg, border, fg, icon, stroke) = switch (step.state) {
      KStepState.done => (
        c.primary,
        c.primary,
        Colors.white,
        KIcons.check,
        3.0,
      ),
      KStepState.now => (
        c.surface,
        c.primary,
        c.primary,
        step.icon ?? KIcons.package,
        2.6,
      ),
      KStepState.bad => (c.badFill, c.badFill, Colors.white, KIcons.close, 3.0),
      KStepState.todo => (c.surface, c.line, c.muted, null, 0.0),
    };
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 2),
        boxShadow: step.state == KStepState.now
            ? [BoxShadow(color: c.tint2, spreadRadius: 4)]
            : null,
      ),
      alignment: Alignment.center,
      child: icon == null
          ? null
          : KIcon(icon, size: 14, color: fg, strokeWidth: stroke),
    );
  }
}

/// Empty / zero state: art circle, title, one line, optional action.
class KEmptyState extends StatelessWidget {
  const KEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final KIconData icon;
  final String title;
  final String? message;
  final Widget? action;

  /// 96 px art instead of 128 (inside cards).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final art = compact ? 96.0 : 128.0;
    return Padding(
      padding: compact
          ? const EdgeInsets.fromLTRB(8, 8, 8, 16)
          : const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: art,
            height: art,
            decoration: BoxDecoration(color: c.tint, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: KIcon(icon, size: compact ? 40 : 56, color: c.brand),
          ),
          const SizedBox(height: 20),
          Text(title, style: k.text.h3, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: k.text.small.copyWith(color: c.muted),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

enum KBannerTone { info, warn, bad, ok }

/// Inline banner with icon. Use [KBanner.rich] to bold the key fact.
class KBanner extends StatelessWidget {
  const KBanner({
    super.key,
    required String this.message,
    this.tone = KBannerTone.info,
    this.icon,
  }) : span = null;

  const KBanner.rich({
    super.key,
    required InlineSpan this.span,
    this.tone = KBannerTone.info,
    this.icon,
  }) : message = null;

  final String? message;
  final InlineSpan? span;
  final KBannerTone tone;

  /// Defaults per tone (time, warning, error, success).
  final KIconData? icon;

  static (Color, Color, Color, KIconData) styleFor(KBannerTone tone) =>
      switch (tone) {
        KBannerTone.info => (
          KColors.sky50,
          KColors.sky100,
          KColors.sky900,
          KIcons.info,
        ),
        KBannerTone.warn => (
          KColors.warnBg,
          KColors.warnLine,
          KColors.warnText,
          KIcons.warning,
        ),
        KBannerTone.bad => (
          KColors.badBg,
          KColors.badLine,
          KColors.badText,
          KIcons.error,
        ),
        KBannerTone.ok => (
          KColors.okBg,
          KColors.okLine,
          KColors.okText,
          KIcons.success,
        ),
      };

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final (bg, border, fg, defaultIcon) = styleFor(tone);
    final style = k.text.small.copyWith(height: 19 / 13, color: fg);
    return Semantics(
      container: true,
      liveRegion: tone == KBannerTone.bad,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(KRadius.box),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: KIcon(icon ?? defaultIcon, size: 20, color: fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: span != null
                  ? Text.rich(span!, style: style)
                  : Text(message!, style: style),
            ),
          ],
        ),
      ),
    );
  }
}
