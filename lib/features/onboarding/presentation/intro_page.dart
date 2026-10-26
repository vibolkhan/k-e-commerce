import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/k_ui.dart';
import '../data/onboarding_store.dart';

/// S-03a–c: three slides (shop, pay with KHQR/COD, same-day delivery),
/// shown once. Skip or "Start shopping" finishes onboarding and the router
/// opens the home (or the link that opened the app).
class IntroPage extends ConsumerStatefulWidget {
  const IntroPage({super.key});

  @override
  ConsumerState<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends ConsumerState<IntroPage> {
  final _pages = PageController();
  var _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _finish() => ref
      .read(onboardingProgressProvider.notifier)
      .complete(OnboardingStep.intro);

  void _next() => _pages.nextPage(
    duration: const Duration(milliseconds: 280),
    curve: Curves.easeOut,
  );

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final slides = [
      _Slide(
        art: const _Art(
          icon: KIcons.package,
          side: KIcons.heart,
          sideColor: KColors.heart,
          badgeIcon: KIcons.star,
          badgeColor: KColors.star,
          badge: '4.8',
        ),
        title: l10n.intro1Title,
        body: l10n.intro1Body,
      ),
      _Slide(
        art: _Art(
          icon: KIcons.khqr,
          side: KIcons.cash,
          sideColor: KColors.ok,
          badgeIcon: KIcons.success,
          badgeColor: KColors.ok,
          badge: l10n.intro2Paid,
        ),
        title: l10n.intro2Title,
        body: l10n.intro2Body,
      ),
      _Slide(
        art: _Art(
          icon: KIcons.delivery,
          side: KIcons.location,
          sideColor: KColors.sky500,
          badgeIcon: KIcons.time,
          badgeColor: KColors.primary,
          badge: l10n.intro3Eta,
        ),
        title: l10n.intro3Title,
        body: l10n.intro3Body,
      ),
    ];
    final last = _index == slides.length - 1;
    return Scaffold(
      backgroundColor: k.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: last
                      ? null
                      : KButton.ghost(
                          key: const Key('intro-skip'),
                          label: l10n.introSkip,
                          size: KButtonSize.sm,
                          onPressed: _finish,
                        ),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _index = i),
                children: slides,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
              child: Column(
                children: [
                  Semantics(
                    label: l10n.introSlideOf(_index + 1, slides.length),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < slides.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _index ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _index
                                  ? k.colors.primary
                                  : k.colors.line2,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  KButton(
                    key: const Key('intro-next'),
                    label: last ? l10n.introStart : l10n.introNext,
                    size: KButtonSize.lg,
                    expand: true,
                    onPressed: last ? _finish : _next,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.art, required this.title, required this.body});

  final Widget art;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
      child: Column(
        children: [
          art,
          const SizedBox(height: 36),
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: k.text.h1.copyWith(fontSize: 28, height: 36 / 28),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            textAlign: TextAlign.center,
            style: k.text.body.copyWith(color: k.colors.muted),
          ),
        ],
      ),
    );
  }
}

/// Decorative: soft sky circles, a main icon tile, a side tile and a pill.
class _Art extends StatelessWidget {
  const _Art({
    required this.icon,
    required this.side,
    required this.sideColor,
    required this.badgeIcon,
    required this.badgeColor,
    required this.badge,
  });

  final KIconData icon;
  final KIconData side;
  final Color sideColor;
  final KIconData badgeIcon;
  final Color badgeColor;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    BoxDecoration tile(double radius) => BoxDecoration(
      color: k.colors.surface,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: k.shadow2,
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 260,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                color: KColors.sky50,
                shape: BoxShape.circle,
              ),
              child: SizedBox.expand(),
            ),
            Container(
              margin: const EdgeInsets.all(36),
              decoration: const BoxDecoration(
                color: KColors.sky100,
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 120,
              height: 120,
              decoration: tile(34),
              alignment: Alignment.center,
              child: KIcon(icon, size: 56, color: k.colors.primary),
            ),
            PositionedDirectional(
              start: 12,
              top: 40,
              child: Container(
                width: 68,
                height: 68,
                decoration: tile(22),
                alignment: Alignment.center,
                child: KIcon(side, size: 30, color: sideColor),
              ),
            ),
            PositionedDirectional(
              end: 20,
              top: 32,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: tile(16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    KIcon(badgeIcon, size: 16, color: badgeColor),
                    const SizedBox(width: 6),
                    Text(
                      badge,
                      style: k.text.small.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
