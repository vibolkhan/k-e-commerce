import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../icons/k_icon.dart';
import '../icons/k_icons.dart';
import '../theme/k_theme.dart';
import '../theme/k_tokens.dart';
import 'k_basics.dart';
import 'k_button.dart';

class KNavItem {
  const KNavItem({
    required this.icon,
    required this.label,
    this.badge,
    this.badgeBlue = false,
  });

  final KIconData icon;
  final String label;
  final int? badge;

  /// Neutral count (quote list, jobs) instead of red alert.
  final bool badgeBlue;
}

/// Bottom navigation, shared by every phone app. Use the named
/// constructors for the role layouts from the Components board.
class KBottomNav extends StatelessWidget {
  const KBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  /// Home, Categories, Cart, Orders, Account.
  factory KBottomNav.customer(
    BuildContext context, {
    Key? key,
    required int currentIndex,
    required ValueChanged<int> onTap,
    int cartCount = 0,
  }) {
    final l = AppLocalizations.of(context);
    return KBottomNav(
      key: key,
      currentIndex: currentIndex,
      onTap: onTap,
      items: [
        KNavItem(icon: KIcons.home, label: l.navHome),
        KNavItem(icon: KIcons.categories, label: l.navCategories),
        KNavItem(icon: KIcons.cart, label: l.navCart, badge: cartCount),
        KNavItem(icon: KIcons.orders, label: l.navOrders),
        KNavItem(icon: KIcons.account, label: l.navAccount),
      ],
    );
  }

  /// Home, Categories, Cart, Account — no orders until signed in.
  factory KBottomNav.guest(
    BuildContext context, {
    Key? key,
    required int currentIndex,
    required ValueChanged<int> onTap,
    int cartCount = 0,
  }) {
    final l = AppLocalizations.of(context);
    return KBottomNav(
      key: key,
      currentIndex: currentIndex,
      onTap: onTap,
      items: [
        KNavItem(icon: KIcons.home, label: l.navHome),
        KNavItem(icon: KIcons.categories, label: l.navCategories),
        KNavItem(icon: KIcons.cart, label: l.navCart, badge: cartCount),
        KNavItem(icon: KIcons.account, label: l.navAccount),
      ],
    );
  }

  /// Business buyer: the cart becomes the quote list.
  factory KBottomNav.business(
    BuildContext context, {
    Key? key,
    required int currentIndex,
    required ValueChanged<int> onTap,
    int quoteListCount = 0,
  }) {
    final l = AppLocalizations.of(context);
    return KBottomNav(
      key: key,
      currentIndex: currentIndex,
      onTap: onTap,
      items: [
        KNavItem(icon: KIcons.home, label: l.navHome),
        KNavItem(icon: KIcons.categories, label: l.navCategories),
        KNavItem(
          icon: KIcons.quote,
          label: l.navQuoteList,
          badge: quoteListCount,
          badgeBlue: true,
        ),
        KNavItem(icon: KIcons.orders, label: l.navOrdersQuotes),
        KNavItem(icon: KIcons.account, label: l.navAccount),
      ],
    );
  }

  /// Jobs, History, Cash, Account.
  factory KBottomNav.rider(
    BuildContext context, {
    Key? key,
    required int currentIndex,
    required ValueChanged<int> onTap,
    int jobCount = 0,
  }) {
    final l = AppLocalizations.of(context);
    return KBottomNav(
      key: key,
      currentIndex: currentIndex,
      onTap: onTap,
      items: [
        KNavItem(
          icon: KIcons.stock,
          label: l.navJobs,
          badge: jobCount,
          badgeBlue: true,
        ),
        KNavItem(icon: KIcons.time, label: l.navHistory),
        KNavItem(icon: KIcons.cash, label: l.navCash),
        KNavItem(icon: KIcons.account, label: l.navAccount),
      ],
    );
  }

  /// Admin on mobile: Dashboard, Orders, RFQs, Chat, More.
  factory KBottomNav.admin(
    BuildContext context, {
    Key? key,
    required int currentIndex,
    required ValueChanged<int> onTap,
    int orderCount = 0,
    int chatCount = 0,
  }) {
    final l = AppLocalizations.of(context);
    return KBottomNav(
      key: key,
      currentIndex: currentIndex,
      onTap: onTap,
      items: [
        KNavItem(icon: KIcons.dashboard, label: l.navDashboard),
        KNavItem(icon: KIcons.orders, label: l.navOrders, badge: orderCount),
        KNavItem(icon: KIcons.quote, label: l.navRfqs),
        KNavItem(icon: KIcons.chat, label: l.navChat, badge: chatCount),
        KNavItem(icon: KIcons.more, label: l.navMore),
      ],
    );
  }

  final List<KNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Semantics(
      container: true,
      label: l10n.navMain,
      explicitChildNodes: true,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.line)),
        ),
        padding: EdgeInsets.fromLTRB(
          4,
          6,
          4,
          bottomInset > 18 ? bottomInset : 18,
        ),
        child: SizedBox(
          height: 55,
          child: Row(
            children: [
              for (final (i, item) in items.indexed)
                Expanded(
                  child: _NavButton(
                    item: item,
                    selected: i == currentIndex,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final KNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final color = selected ? c.primary : c.muted;
    final badge = item.badge ?? 0;
    return Semantics(
      button: true,
      selected: selected,
      label: badge > 0 ? l10n.uiBadgeCount(item.label, badge) : item.label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KRadius.input),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 22,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  KIcon(
                    item.icon,
                    color: color,
                    strokeWidth: selected ? 2.2 : 1.8,
                  ),
                  if (badge > 0)
                    Positioned(
                      top: -6,
                      left: 0,
                      right: 0,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Transform.translate(
                          offset: const Offset(13, 0),
                          child: KBadge(badge, blue: item.badgeBlue),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            // Long labels ("Orders & quotes") shrink rather than truncate.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                item.label,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: k.text.caption.copyWith(
                  fontSize: 11,
                  height: 14 / 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 56 px app bar: back button, centred (or left) title, icon actions.
class KAppBar extends StatelessWidget implements PreferredSizeWidget {
  const KAppBar({
    super.key,
    this.title,
    this.centerTitle = true,
    this.actions = const [],
    this.showBack,
    this.onBack,
    this.line = false,
    this.transparent = false,
  });

  final String? title;
  final bool centerTitle;

  /// Usually [KIconButton]s.
  final List<Widget> actions;

  /// Defaults to whether the route can pop.
  final bool? showBack;
  final VoidCallback? onBack;

  /// Bottom border.
  final bool line;
  final bool transparent;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final back = showBack ?? Navigator.maybeOf(context)?.canPop() ?? false;
    final leading = back
        ? KIconButton(
            icon: KIcons.back,
            label: l10n.uiBack,
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
          )
        : null;
    final titleText = title == null
        ? const SizedBox()
        : Semantics(
            header: true,
            child: Text(
              title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: centerTitle ? TextAlign.center : TextAlign.start,
              style: k.text.h3,
            ),
          );
    // Balance the centred title against the wider side.
    final sideCount = actions.length > (leading == null ? 0 : 1)
        ? actions.length
        : (leading == null ? 0 : 1);
    final sideWidth = sideCount == 0
        ? 0.0
        : sideCount * kMinTap + (sideCount - 1) * 4;
    return Material(
      color: transparent ? Colors.transparent : c.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: line
              ? BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.line)),
                )
              : null,
          child: Row(
            children: [
              if (centerTitle)
                SizedBox(
                  width: sideWidth,
                  child: Align(alignment: Alignment.centerLeft, child: leading),
                )
              else
                ?leading,
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: !centerTitle && leading == null ? 8 : 0,
                  ),
                  child: titleText,
                ),
              ),
              if (centerTitle)
                SizedBox(
                  width: sideWidth,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: _spaced(actions),
                  ),
                )
              else
                ..._spaced(actions),
            ],
          ),
        ),
      ),
    );
  }

  static List<Widget> _spaced(List<Widget> items) => [
    for (final (i, a) in items.indexed) ...[
      if (i > 0) const SizedBox(width: 4),
      a,
    ],
  ];
}
