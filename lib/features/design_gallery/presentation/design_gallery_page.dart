import 'package:flutter/material.dart';

import '../../../core/domain/statuses.dart';
import '../../../core/ui/k_ui.dart';

// Developer-only page (not registered in prod). The copy below is sample
// data mirroring the design boards, so it is deliberately not in the ARB
// files; component-owned strings still come from l10n.

/// Every K component on one page, laid out like the Brand, Components and
/// Overlays boards. Open at `/design-gallery` in dev and staging builds.
class DesignGalleryPage extends StatelessWidget {
  const DesignGalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Scaffold(
      backgroundColor: k.colors.bg,
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 1200;
          final gutter = wide ? 80.0 : 16.0;
          return ListView(
            padding: EdgeInsets.fromLTRB(gutter, wide ? 64 : 24, gutter, 64),
            children: [
              const _BrandBoard(),
              const SizedBox(height: 64),
              _Board(
                overline: 'Components',
                title: 'Building blocks',
                lead:
                    'Every screen is assembled from these parts, styled by '
                    'one shared theme. Change a token once and every screen '
                    'follows.',
                wide: wide,
                columns: const [
                  [
                    _ButtonsCard(),
                    _FieldsCard(),
                    _ChoicesCard(),
                    _ChipsTabsCard(),
                  ],
                  [
                    _PillsCard(),
                    _ProductCardsCard(),
                    _CartLineCard(),
                    _BannersCard(),
                  ],
                  [
                    _AppBarsCard(),
                    _BottomNavCard(),
                    _ListRowsCard(),
                    _TimelineCard(),
                    _EmptyCard(),
                  ],
                ],
              ),
              const SizedBox(height: 64),
              _OverlaysBoard(wide: wide),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- layout

class _Board extends StatelessWidget {
  const _Board({
    required this.overline,
    required this.title,
    required this.lead,
    required this.columns,
    required this.wide,
  });

  final String overline;
  final String title;
  final String lead;
  final List<List<Widget>> columns;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BoardHeader(overline: overline, title: title, lead: lead),
        const SizedBox(height: 32),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, col) in columns.indexed) ...[
                if (i > 0) const SizedBox(width: 24),
                Expanded(child: _Stack(children: col)),
              ],
            ],
          )
        else
          _Stack(children: [for (final col in columns) ...col]),
      ],
    );
  }
}

class _Stack extends StatelessWidget {
  const _Stack({required this.children, this.gap = 24});
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, c) in children.indexed) ...[
        if (i > 0) SizedBox(height: gap),
        c,
      ],
    ],
  );
}

class _BoardHeader extends StatelessWidget {
  const _BoardHeader({
    required this.overline,
    required this.title,
    required this.lead,
  });

  final String overline;
  final String title;
  final String lead;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 32,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _SgTitle(overline),
            const SizedBox(height: 4),
            Text(
              title,
              style: k.text.display.copyWith(
                fontSize: 40,
                height: 48 / 40,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            lead,
            style: k.text.small.copyWith(
              fontSize: 14,
              height: 21 / 14,
              color: k.colors.ink3,
            ),
          ),
        ),
      ],
    );
  }
}

/// Board section label: 13/18/800, primary ink, tracked caps.
class _SgTitle extends StatelessWidget {
  const _SgTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Text(
      text.toUpperCase(),
      style: k.text.label.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 1.04,
        color: k.colors.primaryInk,
      ),
    );
  }
}

/// A board card: title then children 14 px apart.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.padding = const EdgeInsets.all(24),
    this.gap = 14,
  });

  final String title;
  final List<Widget> children;
  final EdgeInsets padding;
  final double gap;

  @override
  Widget build(BuildContext context) => KCard(
    padding: padding,
    child: _Stack(gap: gap, children: [_SgTitle(title), ...children]),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: context.k.text.label);
}

class _Help extends StatelessWidget {
  const _Help(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.k.text.caption.copyWith(
      fontWeight: FontWeight.w400,
      color: context.k.colors.muted,
    ),
  );
}

Widget _row(List<Widget> children, {double gap = 12}) => Row(
  children: [
    for (final (i, c) in children.indexed) ...[
      if (i > 0) SizedBox(width: gap),
      Expanded(child: c),
    ],
  ],
);

void _noop() {}

// ---------------------------------------------------------------- brand

class _BrandBoard extends StatelessWidget {
  const _BrandBoard();

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    Widget swatch(Color color, String name, String note, {double h = 56}) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: h,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x140F172A)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              style: k.text.caption.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(note, style: k.text.caption.copyWith(color: c.muted)),
          ],
        );

    final typeRows = <(String, TextStyle, String)>[
      ('Display · 32/40 · 800', k.text.display, 'Same-day before 3 PM'),
      ('Heading 1 · 24/32 · 800', k.text.h1, 'Wireless Headphones Pro'),
      ('Heading 2 · 20/28 · 700', k.text.h2, 'Order summary'),
      ('Heading 3 · 17/24 · 700', k.text.h3, 'Delivery address'),
      (
        'Body · 15/22 · 400',
        k.text.body,
        'Order before 3:00 PM and we deliver today.',
      ),
      ('Label · 13/18 · 600', k.text.label, 'Phone number'),
      ('Small · 13/18 · 400', k.text.small, 'Prices include VAT.'),
      (
        'Caption · 12/16 · 500',
        k.text.caption.copyWith(color: c.muted),
        'Updated 2 min ago',
      ),
      ('Overline · 12/16 · 700', k.text.overline, 'BEST SELLERS'),
      ('Price · 24/32 · 800', k.text.price, r'$49.00'),
      ('Khmer · Kantumruy Pro', k.text.h3, 'ដឹកជញ្ជូនថ្ងៃនេះ'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 40,
          runSpacing: 24,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const KAppIcon(size: 128),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SgTitle('K E-Commerce · design system · F02'),
                  const SizedBox(height: 8),
                  Text(
                    'Brand & foundations',
                    style: k.text.display.copyWith(
                      fontSize: 44,
                      height: 52 / 44,
                      letterSpacing: -1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sky blue leads; slate neutrals keep every screen calm and '
                    'easy to read.',
                    style: k.text.body.copyWith(
                      fontSize: 17,
                      height: 26 / 17,
                      color: c.ink2,
                    ),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _LogoTile(
                  color: c.surface,
                  border: true,
                  child: const KLogo(size: 56),
                ),
                _LogoTile(color: c.brand, child: const KLogo.white(size: 56)),
                _LogoTile(color: c.ink, child: const KLogo.onInk(size: 56)),
                _LogoTile(
                  color: c.surface,
                  border: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const KLogo(size: 24),
                      const SizedBox(width: 14),
                      Text(
                        'Min. 20 px',
                        style: k.text.caption.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 56),
        LayoutBuilder(
          builder: (context, box) {
            final colour = _Stack(
              gap: 20,
              children: [
                const _SgTitle('Colour'),
                _grid(3, [
                  swatch(
                    KColors.sky500,
                    'Sky 500 · Brand',
                    '#0EA5E9 · logo only',
                    h: 88,
                  ),
                  swatch(
                    KColors.primary,
                    'Primary',
                    '#0272B6 · actions',
                    h: 88,
                  ),
                  swatch(
                    KColors.primaryInk,
                    'Primary ink',
                    '#025A91 · on tints',
                    h: 88,
                  ),
                ]),
                _grid(6, [
                  swatch(KColors.sky50, 'Sky 50', '#F0F9FF'),
                  swatch(KColors.sky100, 'Sky 100', '#E0F2FE'),
                  swatch(KColors.sky300, 'Sky 300', '#7DD3FC'),
                  swatch(KColors.bg, 'Background', '#F8FAFC'),
                  swatch(KColors.soft, 'Soft', '#F1F5F9'),
                  swatch(KColors.line, 'Line', '#E2E8F0'),
                ]),
                _grid(4, [
                  swatch(KColors.ink, 'Ink · text', '#0F172A'),
                  swatch(KColors.ink2, 'Slate 700', '#334155'),
                  swatch(KColors.ink3, 'Slate 600', '#475569'),
                  swatch(KColors.muted, 'Slate 500', '#64748B'),
                ]),
                _grid(4, [
                  swatch(KColors.okBg, 'Success', '#047857 on #ECFDF5'),
                  swatch(KColors.warnBg, 'Warning', '#B45309 on #FFF7ED'),
                  swatch(KColors.badBg, 'Danger', '#B91C1C on #FEF2F2'),
                  swatch(KColors.badFill, 'Danger fill', '#DC2626'),
                ]),
              ],
            );
            final type = _Stack(
              gap: 20,
              children: [
                const _SgTitle('Typography'),
                KCard(
                  padding: EdgeInsets.zero,
                  child: KList(
                    children: [
                      for (final (label, style, sample) in typeRows)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              SizedBox(
                                width: 170,
                                child: Text(
                                  label,
                                  style: k.text.caption.copyWith(
                                    color: c.muted,
                                  ),
                                ),
                              ),
                              Expanded(child: Text(sample, style: style)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
            if (box.maxWidth < 1000) {
              return _Stack(gap: 40, children: [colour, type]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: colour),
                const SizedBox(width: 56),
                Expanded(child: type),
              ],
            );
          },
        ),
        const SizedBox(height: 56),
        const _SgTitle('Iconography'),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (name, icon) in _iconTiles)
              Container(
                width: 92,
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 12),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(KRadius.input),
                ),
                child: Column(
                  children: [
                    KIcon(icon, size: 24, color: c.ink),
                    const SizedBox(height: 8),
                    Text(
                      name,
                      style: k.text.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: c.ink2,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 56),
        Wrap(
          spacing: 40,
          runSpacing: 32,
          children: [
            _FoundationBlock(
              title: 'Spacing',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in const [
                    KSpacing.x1,
                    KSpacing.x2,
                    KSpacing.x3,
                    KSpacing.x4,
                    KSpacing.x6,
                    KSpacing.x8,
                    KSpacing.x12,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text(
                              s.toInt().toString(),
                              style: k.text.caption.copyWith(color: c.muted),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: s,
                            height: 12,
                            decoration: BoxDecoration(
                              color: s < 16
                                  ? KColors.sky300
                                  : s < 32
                                  ? KColors.sky400
                                  : KColors.sky500,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            _FoundationBlock(
              title: 'Radius',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (r, name) in const [
                    (KRadius.tag, '8 · tags'),
                    (KRadius.input, '12 · inputs'),
                    (KRadius.card, '16 · cards'),
                    (KRadius.sheet, '24 · sheets'),
                    (KRadius.pill, 'Pill'),
                  ])
                    Column(
                      children: [
                        Container(
                          width: 64,
                          height: r == KRadius.pill ? 32 : 64,
                          margin: EdgeInsets.symmetric(
                            vertical: r == KRadius.pill ? 16 : 0,
                          ),
                          decoration: BoxDecoration(
                            color: KColors.sky100,
                            border: Border.all(color: KColors.sky200),
                            borderRadius: r == KRadius.sheet
                                ? const BorderRadius.vertical(
                                    top: Radius.circular(KRadius.sheet),
                                  )
                                : BorderRadius.circular(r),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          name,
                          style: k.text.caption.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            _FoundationBlock(
              title: 'Elevation',
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.bg,
                  borderRadius: BorderRadius.circular(KRadius.card),
                ),
                child: Row(
                  children: [
                    for (final (i, (shadow, name)) in [
                      (k.shadow1, 'Level 1\ncards'),
                      (k.shadow2, 'Level 2\nfloating'),
                      (k.shadow3, 'Level 3\noverlays'),
                    ].indexed) ...[
                      if (i > 0) const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          height: 88,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: shadow,
                          ),
                          child: Text(
                            name,
                            textAlign: TextAlign.center,
                            style: k.text.caption.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _grid(int count, List<Widget> children) => LayoutBuilder(
    builder: (context, box) {
      final perRow = box.maxWidth < 480 ? (count / 2).ceil() : count;
      final width = (box.maxWidth - (perRow - 1) * 12) / perRow;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [for (final c in children) SizedBox(width: width, child: c)],
      );
    },
  );
}

const _iconTiles = [
  ('Home', KIcons.home),
  ('Categories', KIcons.categories),
  ('Cart', KIcons.cart),
  ('Orders', KIcons.orders),
  ('Account', KIcons.account),
  ('Search', KIcons.search),
  ('Notifications', KIcons.notifications),
  ('Wishlist', KIcons.heart),
  ('Filter', KIcons.filter),
  ('Sort', KIcons.sort),
  ('Rating', KIcons.star),
  ('Location', KIcons.location),
  ('Delivery', KIcons.delivery),
  ('Time', KIcons.time),
  ('KHQR', KIcons.khqr),
  ('Cash', KIcons.cash),
  ('Bank', KIcons.bank),
  ('Quote', KIcons.quote),
  ('Business', KIcons.business),
  ('Upload', KIcons.upload),
  ('Camera', KIcons.camera),
  ('Call', KIcons.call),
  ('Chat', KIcons.chat),
  ('Return', KIcons.returnItem),
  ('Invoice', KIcons.invoice),
  ('Delete', KIcons.delete),
  ('Edit', KIcons.edit),
  ('Info', KIcons.info),
  ('Warning', KIcons.warning),
  ('Success', KIcons.success),
  ('Language', KIcons.language),
  ('Rider', KIcons.rider),
  ('Stock', KIcons.stock),
  ('Reports', KIcons.reports),
  ('Support', KIcons.support),
  ('Date', KIcons.date),
];

class _LogoTile extends StatelessWidget {
  const _LogoTile({
    required this.color,
    required this.child,
    this.border = false,
  });
  final Color color;
  final Widget child;
  final bool border;

  @override
  Widget build(BuildContext context) => Container(
    width: 144,
    height: 96,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(KRadius.card),
      border: border ? Border.all(color: context.k.colors.line) : null,
    ),
    child: child,
  );
}

class _FoundationBlock extends StatelessWidget {
  const _FoundationBlock({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 400,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_SgTitle(title), const SizedBox(height: 16), child],
    ),
  );
}

// ---------------------------------------------------------------- components

class _ButtonsCard extends StatelessWidget {
  const _ButtonsCard();

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Buttons',
    children: [
      const KButton(
        label: 'Primary · Place order',
        onPressed: _noop,
        expand: true,
      ),
      const KButton.tonal(
        label: 'Tonal · Add to quote',
        onPressed: _noop,
        expand: true,
      ),
      const KButton.outline(
        label: 'Outline · Change address',
        onPressed: _noop,
        expand: true,
      ),
      _row([
        const KButton.ghost(label: 'Ghost', onPressed: _noop, expand: true),
        const KButton.danger(label: 'Delete', onPressed: _noop, expand: true),
        const KButton(
          label: 'Cancel order',
          variant: KButtonVariant.dangerOutline,
          onPressed: _noop,
          expand: true,
        ),
      ]),
      _row([
        const KButton(label: 'Disabled', onPressed: null, expand: true),
        const KButton(
          label: 'Place order',
          loadingLabel: 'Placing…',
          loading: true,
          expand: true,
          onPressed: _noop,
        ),
      ]),
      const Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          KButton(label: 'Large 56', size: KButtonSize.lg, onPressed: _noop),
          KButton(label: 'Medium 48', onPressed: _noop),
          KButton(label: 'Small 36', size: KButtonSize.sm, onPressed: _noop),
        ],
      ),
      const _Help(
        'Small buttons only inside cards and tables; each still has a 44 px '
        'tap area.',
      ),
    ],
  );
}

class _FieldsCard extends StatelessWidget {
  const _FieldsCard();

  @override
  Widget build(BuildContext context) => const _Section(
    title: 'Text fields',
    children: [
      KTextField(
        label: 'Phone number',
        prefixText: '+855',
        initialValue: '12 345 678',
        keyboardType: TextInputType.phone,
      ),
      KTextField(label: 'Full name', initialValue: 'Dara Sok'),
      KTextField(
        label: 'VAT TIN',
        initialValue: 'K001-10023',
        errorText: 'Enter the full 14-character TIN, e.g. K001-100234567',
      ),
      KTextField(
        label: 'Return reason',
        initialValue: 'Item arrived damaged',
        readOnly: true,
        suffix: KIcon(KIcons.chevronDown, size: 20),
      ),
      KTextField(
        label: 'Note to rider',
        optional: true,
        hint: 'Gate code, landmark, best time to call',
        maxLines: 4,
      ),
      KTextField.search(hint: 'Search products'),
      KTextField(
        label: 'Phone (verified)',
        initialValue: '+855 12 345 678',
        enabled: false,
        helpText: 'Change it from Account › Phone.',
      ),
    ],
  );
}

class _ChoicesCard extends StatefulWidget {
  const _ChoicesCard();

  @override
  State<_ChoicesCard> createState() => _ChoicesCardState();
}

class _ChoicesCardState extends State<_ChoicesCard> {
  bool _khqr = true;
  bool _email = true;
  bool _orderUpdates = true;
  bool _reviews = false;
  bool _otpError = false;
  final _otp = TextEditingController(text: '4829');

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return _Section(
      title: 'Code, choices & toggles',
      children: [
        KOtpField(
          error: _otpError,
          controller: _otp,
          onCompleted: (code) => setState(() => _otpError = code != '482913'),
        ),
        KOptionTile(
          title: 'KHQR',
          subtitle: 'Pay with any Cambodian banking app',
          icon: KIcons.khqr,
          selected: _khqr,
          onTap: () => setState(() => _khqr = true),
        ),
        KOptionTile(
          title: 'Cash on delivery',
          subtitle: 'Pay the rider when it arrives',
          icon: KIcons.cash,
          selected: !_khqr,
          onTap: () => setState(() => _khqr = false),
        ),
        MergeSemantics(
          child: Row(
            children: [
              Checkbox(
                value: _email,
                onChanged: (v) => setState(() => _email = v!),
              ),
              Expanded(
                child: Text(
                  'Send me order updates by email',
                  style: k.text.small.copyWith(fontSize: 14, height: 20 / 14),
                ),
              ),
            ],
          ),
        ),
        KSwitchRow(
          label: 'Order updates',
          value: _orderUpdates,
          onChanged: (v) => setState(() => _orderUpdates = v),
        ),
        KSwitchRow(
          label: 'Review reminders',
          value: _reviews,
          onChanged: (v) => setState(() => _reviews = v),
        ),
      ],
    );
  }
}

class _ChipsTabsCard extends StatefulWidget {
  const _ChipsTabsCard();

  @override
  State<_ChipsTabsCard> createState() => _ChipsTabsCardState();
}

class _ChipsTabsCardState extends State<_ChipsTabsCard> {
  int _chip = 0;
  String _seg = 'phone';
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Chips, segmented & tabs',
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final (i, label) in ['All', 'Audio', 'Wearables'].indexed)
              KChip(
                label: label,
                selected: _chip == i,
                onTap: () => setState(() => _chip = i),
              ),
            const KChip(
              label: 'Filters',
              icon: KIcons.filter,
              count: 2,
              onTap: _noop,
            ),
          ],
        ),
        KSegmented<String>(
          segments: const [
            KSegment('phone', 'Phone'),
            KSegment('email', 'Email'),
          ],
          selected: _seg,
          onChanged: (v) => setState(() => _seg = v),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(KRadius.box),
          child: KTabs(
            selectedIndex: _tab,
            onChanged: (i) => setState(() => _tab = i),
            tabs: const [
              KTab('Active', count: 2),
              KTab('Completed', count: 14),
              KTab('Cancelled'),
            ],
          ),
        ),
      ],
    );
  }
}

class _PillsCard extends StatelessWidget {
  const _PillsCard();

  @override
  Widget build(BuildContext context) {
    Widget wrap(List<Widget> pills) =>
        Wrap(spacing: 8, runSpacing: 8, children: pills);
    return _Section(
      title: 'Status pills',
      children: [
        const _Label('Order'),
        wrap([for (final s in OrderStatus.values) KStatusPill.order(s)]),
        const _Label('Payment'),
        wrap([for (final s in PaymentStatus.values) KStatusPill.payment(s)]),
        const _Label('Quote request'),
        wrap([for (final s in QuoteStatus.values) KStatusPill.quote(s)]),
        const _Label('Return · business · review · rider job'),
        wrap([
          for (final s in ReturnStatus.values) KStatusPill.returns(s),
          KStatusPill.business(BusinessVerificationStatus.pending),
          KStatusPill.business(BusinessVerificationStatus.verified),
          for (final s in ReviewStatus.values) KStatusPill.review(s),
          for (final s in RiderJobStatus.values) KStatusPill.riderJob(s),
        ]),
      ],
    );
  }
}

const _catalogue = [
  ('Headphones \$49', KIcons.headphones, KArtTone.a),
  ('Smart watch \$79', KIcons.watch, KArtTone.b),
  ('Sneakers \$59', KIcons.sneaker, KArtTone.g),
  ('Backpack \$35', KIcons.backpack, KArtTone.d),
  ('Mug set \$18', KIcons.mug, KArtTone.e),
  ('Desk lamp \$24', KIcons.lamp, KArtTone.f),
  ('Bottle \$12.50', KIcons.bottle, KArtTone.a),
  ('T-shirt \$9.90', KIcons.tshirt, KArtTone.b),
  ('Speaker \$29', KIcons.speaker, KArtTone.f),
  ('A4 paper \$5.20', KIcons.paper, KArtTone.c),
  ('Rice cooker \$45', KIcons.riceCooker, KArtTone.d),
  ('Phone case \$8', KIcons.phoneCase, KArtTone.e),
];

class _ProductCardsCard extends StatefulWidget {
  const _ProductCardsCard();

  @override
  State<_ProductCardsCard> createState() => _ProductCardsCardState();
}

class _ProductCardsCardState extends State<_ProductCardsCard> {
  bool _wish = true;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return _Section(
      title: 'Product cards',
      children: [
        _row([
          KProductCard(
            name: 'Wireless Headphones Pro',
            image: const KProductArt(icon: KIcons.headphones, radius: 0),
            price: r'$49.00',
            khrAmount: '200,900',
            rating: 4.6,
            ratingCount: 128,
            wishlisted: _wish,
            onWishlist: () => setState(() => _wish = !_wish),
            onTap: _noop,
          ),
          const KProductCard.business(
            name: 'A4 Copy Paper, 80 gsm (500 sheets)',
            image: KProductArt(icon: KIcons.paper, tone: KArtTone.c, radius: 0),
            minQuantity: '20 reams',
            rating: 4.7,
            ratingCount: 64,
            onTap: _noop,
          ),
        ]),
        const _Help(
          'Left: retail card with wishlist. Right: business-buyer card — '
          'prices are never shown, only “Price on quote” and the minimum '
          'quantity.',
        ),
        const _Label('Sample catalogue used in mockups'),
        LayoutBuilder(
          builder: (context, box) {
            final w = (box.maxWidth - 3 * 8) / 4;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (name, icon, tone) in _catalogue)
                  SizedBox(
                    width: w,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        KProductArt(icon: icon, tone: tone, radius: 10),
                        const SizedBox(height: 4),
                        Text(name, style: k.text.caption),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CartLineCard extends StatefulWidget {
  const _CartLineCard();

  @override
  State<_CartLineCard> createState() => _CartLineCardState();
}

class _CartLineCardState extends State<_CartLineCard> {
  int _qty = 1;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    return _Section(
      title: 'Cart line, quantity & rating',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 80,
              child: KProductArt(
                icon: KIcons.mug,
                tone: KArtTone.e,
                radius: KRadius.input,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ceramic Coffee Mug Set (4 pcs)',
                    maxLines: 2,
                    style: k.text.body.copyWith(
                      fontSize: 14,
                      height: 19 / 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Colour: Sand',
                    style: k.text.caption.copyWith(color: c.muted),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r'$18.00',
                          style: k.text.body.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      KQtyStepper(
                        value: _qty,
                        max: 5,
                        onChanged: (v) => setState(() => _qty = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        Divider(color: c.line, height: 1),
        Row(
          children: [
            const KStars(rating: 4),
            const SizedBox(width: 12),
            Text(
              '4.0',
              style: k.text.small.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              ' · 128 reviews',
              style: k.text.small.copyWith(color: c.muted),
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(r'$49.00', style: k.text.price),
            const SizedBox(width: 10),
            Text('≈ KHR 200,900', style: k.text.small.copyWith(color: c.muted)),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Free delivery unlocked',
                    style: k.text.small.copyWith(
                      fontWeight: FontWeight.w600,
                      color: c.ok,
                    ),
                  ),
                ),
                Text(
                  r'$92.00 / $50.00',
                  style: k.text.small.copyWith(color: c.muted),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const KProgressBar(value: 1, ok: true),
          ],
        ),
      ],
    );
  }
}

class _BannersCard extends StatelessWidget {
  const _BannersCard();

  @override
  Widget build(BuildContext context) => const _Section(
    title: 'Inline banners',
    gap: 12,
    children: [
      KBanner.rich(
        icon: KIcons.time,
        span: TextSpan(
          children: [
            TextSpan(text: 'Order within '),
            TextSpan(
              text: '4h 35m',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: ' for delivery today.'),
          ],
        ),
      ),
      KBanner(
        tone: KBannerTone.warn,
        message: r'Return delivery ($2.00) is paid by you.',
      ),
      KBanner(
        tone: KBannerTone.bad,
        message: 'Desk lamp is now out of stock. Remove it to continue.',
      ),
      KBanner(
        tone: KBannerTone.ok,
        message: 'Payment received. Your order is confirmed.',
      ),
    ],
  );
}

class _Bordered extends StatelessWidget {
  const _Bordered({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      border: Border.all(color: context.k.colors.line),
      borderRadius: BorderRadius.circular(KRadius.box),
    ),
    child: child,
  );
}

class _AppBarsCard extends StatelessWidget {
  const _AppBarsCard();

  @override
  Widget build(BuildContext context) => const _Section(
    title: 'App bars',
    padding: EdgeInsets.all(10),
    gap: 12,
    children: [
      _Bordered(
        child: KAppBar(
          title: 'Checkout',
          showBack: true,
          onBack: _noop,
          line: true,
        ),
      ),
      _Bordered(
        child: KAppBar(
          title: 'Audio',
          centerTitle: false,
          showBack: true,
          onBack: _noop,
          actions: [
            KIconButton(icon: KIcons.search, label: 'Search', onPressed: _noop),
            KIconButton(
              icon: KIcons.cart,
              label: 'Cart, 3 items',
              badge: 3,
              onPressed: _noop,
            ),
          ],
        ),
      ),
    ],
  );
}

class _BottomNavCard extends StatefulWidget {
  const _BottomNavCard();

  @override
  State<_BottomNavCard> createState() => _BottomNavCardState();
}

class _BottomNavCardState extends State<_BottomNavCard> {
  final _index = <String, int>{
    'Customer': 0,
    'Business buyer': 2,
    'Guest': 3,
    'Rider': 0,
    'Admin (mobile)': 0,
  };

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    KBottomNav nav(String name) {
      void tap(int i) => setState(() => _index[name] = i);
      final i = _index[name]!;
      return switch (name) {
        'Customer' => KBottomNav.customer(
          context,
          currentIndex: i,
          onTap: tap,
          cartCount: 3,
        ),
        'Business buyer' => KBottomNav.business(
          context,
          currentIndex: i,
          onTap: tap,
          quoteListCount: 4,
        ),
        'Guest' => KBottomNav.guest(context, currentIndex: i, onTap: tap),
        'Rider' => KBottomNav.rider(
          context,
          currentIndex: i,
          onTap: tap,
          jobCount: 4,
        ),
        _ => KBottomNav.admin(
          context,
          currentIndex: i,
          onTap: tap,
          orderCount: 12,
          chatCount: 2,
        ),
      };
    }

    return _Section(
      title: 'Bottom navigation · shared component',
      padding: const EdgeInsets.all(10),
      gap: 10,
      children: [
        for (final name in _index.keys) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              name,
              style: k.text.caption.copyWith(color: k.colors.muted),
            ),
          ),
          _Bordered(
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: nav(name),
            ),
          ),
        ],
      ],
    );
  }
}

class _ListRowsCard extends StatelessWidget {
  const _ListRowsCard();

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    return KCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: _SgTitle('List rows'),
          ),
          const KList(
            children: [
              KListRow(
                icon: KIcons.location,
                title: 'Addresses',
                subtitle: '2 saved · Home is default',
                onTap: _noop,
              ),
              KListRow(
                icon: KIcons.language,
                title: 'Language',
                subtitle: 'English',
                onTap: _noop,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: KCard(
              padding: const EdgeInsets.all(14),
              child: _Stack(
                gap: 10,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '#K-10248',
                          style: k.text.body.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      KStatusPill.order(OrderStatus.outForDelivery),
                    ],
                  ),
                  Text(
                    'Today, 10:24 AM · 3 items · KHQR paid',
                    style: k.text.small.copyWith(color: c.muted),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r'$92.00',
                          style: k.text.body.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const KButton.tonal(
                        label: 'Track order',
                        size: KButtonSize.sm,
                        onPressed: _noop,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard();

  @override
  Widget build(BuildContext context) => const _Section(
    title: 'Status timeline',
    children: [
      KTimeline(
        steps: [
          KTimelineStep(
            title: 'Order placed',
            subtitle: 'Today, 10:24 AM',
            state: KStepState.done,
          ),
          KTimelineStep(
            title: 'Payment confirmed',
            subtitle: 'KHQR · 10:26 AM',
            state: KStepState.done,
          ),
          KTimelineStep(
            title: 'Packing',
            subtitle: 'Your items are being packed',
            state: KStepState.now,
          ),
          KTimelineStep(title: 'Out for delivery', state: KStepState.todo),
          KTimelineStep(title: 'Delivered', state: KStepState.todo),
        ],
      ),
    ],
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) => const _Section(
    title: 'Empty state, avatars & loading',
    gap: 12,
    children: [
      KEmptyState(
        compact: true,
        icon: KIcons.heart,
        title: 'No saved items yet',
        message: 'Tap the heart on any product to save it here.',
        action: KButton.tonal(
          label: 'Browse products',
          size: KButtonSize.sm,
          onPressed: _noop,
        ),
      ),
      Row(
        children: [
          KAvatar('DS'),
          SizedBox(width: 10),
          KAvatar('SC', tone: KAvatarTone.amber),
          SizedBox(width: 10),
          KAvatar('VK', tone: KAvatarTone.green),
          SizedBox(width: 10),
          KAvatar('SP', tone: KAvatarTone.violet),
          SizedBox(width: 10),
          KAvatar('CL', tone: KAvatarTone.grey),
          SizedBox(width: 10),
          KBadge(3),
          SizedBox(width: 10),
          KBadge(12, blue: true),
          SizedBox(width: 10),
          KDot(),
        ],
      ),
      Row(
        children: [
          KSkeleton(width: 64, height: 64, radius: 12),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(widthFactor: .8, child: KSkeleton()),
                SizedBox(height: 8),
                FractionallySizedBox(widthFactor: .5, child: KSkeleton()),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

// ---------------------------------------------------------------- overlays

class _OverlaysBoard extends StatelessWidget {
  const _OverlaysBoard({required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final frames = [
      const _Figure(
        caption: 'Confirm dialog.',
        detail:
            ' Icon, short title, one-sentence consequence, two actions. The '
            'safe choice is the primary button.',
        child: _Frame(
          background: _SkeletonPage(),
          overlay: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: KConfirmDialog(
                icon: KIcons.time,
                title: 'Leave payment?',
                message:
                    'Your order is held for 14:32. If it isn’t paid in time, it '
                    'is cancelled and the items go back on sale.',
                cancelLabel: 'Leave',
                confirmLabel: 'Stay and pay',
                onCancel: _noop,
                onConfirm: _noop,
              ),
            ),
          ),
        ),
      ),
      const _Figure(
        caption: 'Destructive confirm.',
        detail:
            ' Red icon and red action, and the action names what happens — '
            'never just “OK”.',
        child: _Frame(
          background: _SkeletonPage(cards: true),
          overlay: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: KConfirmDialog(
                tone: KConfirmTone.destructive,
                title: 'Remove from cart?',
                message:
                    'Wireless Headphones Pro will be removed from your cart.',
                cancelLabel: 'Keep it',
                confirmLabel: 'Remove',
                alternativeLabel: 'Move to wishlist instead',
                onCancel: _noop,
                onConfirm: _noop,
                onAlternative: _noop,
              ),
            ),
          ),
        ),
      ),
      const _Figure(
        caption: 'Bottom sheet.',
        detail:
            ' Grab handle, title, close button. Used for filters, options, '
            'pickers and short forms.',
        child: _Frame(
          background: _SkeletonPage(grid: true),
          overlay: Align(
            alignment: Alignment.bottomCenter,
            child: KBottomSheet(
              title: 'Sort by',
              onClose: _noop,
              child: _SortList(),
            ),
          ),
        ),
      ),
    ];
    final feedback = [
      _Stack(
        gap: 12,
        children: [
          const _Label('Toasts · bottom, 4 seconds'),
          const KToast(
            message: 'Added to cart',
            actionLabel: 'View cart',
            onAction: _noop,
          ),
          const KToast(
            message: 'Item removed',
            tone: KToastTone.info,
            icon: KIcons.delete,
            actionLabel: 'Undo',
            onAction: _noop,
          ),
          const KToast(
            message: 'No connection. We’ll retry automatically.',
            tone: KToastTone.bad,
          ),
          Builder(
            builder: (context) => KButton.outline(
              label: 'Show a toast',
              size: KButtonSize.sm,
              onPressed: () => showKToast(
                context,
                message: 'Added to cart',
                actionLabel: 'View cart',
                onAction: _noop,
              ),
            ),
          ),
        ],
      ),
      _Stack(
        gap: 12,
        children: [
          const _Label('Try the real overlays'),
          Builder(
            builder: (context) => KButton.outline(
              label: 'Open confirm dialog',
              expand: true,
              onPressed: () => showKConfirm(
                context,
                title: 'Place this order?',
                message: r'We will charge $92.00 by KHQR.',
                cancelLabel: 'Not yet',
                confirmLabel: 'Place order',
              ),
            ),
          ),
          Builder(
            builder: (context) => KButton.outline(
              label: 'Open destructive dialog',
              expand: true,
              onPressed: () => showKConfirm(
                context,
                tone: KConfirmTone.destructive,
                title: 'Delete this address?',
                message: 'Home (Toul Kork) will be removed from your account.',
                cancelLabel: 'Keep it',
                confirmLabel: 'Delete address',
              ),
            ),
          ),
          Builder(
            builder: (context) => KButton.outline(
              label: 'Open bottom sheet',
              expand: true,
              onPressed: () => showKBottomSheet<void>(
                context,
                title: 'Sort by',
                builder: (_) => const _SortList(),
              ),
            ),
          ),
        ],
      ),
      _Stack(
        gap: 12,
        children: [
          const _Label('Blocking progress'),
          Container(
            height: 150,
            decoration: BoxDecoration(
              color: k.colors.bg,
              border: Border.all(color: k.colors.line),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              color: Colors.white.withValues(alpha: .7),
              alignment: Alignment.center,
              child: const KBlockingProgress(
                message: 'Confirming your payment…',
              ),
            ),
          ),
        ],
      ),
    ];

    Widget grid(List<Widget> items) => wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, f) in items.indexed) ...[
                if (i > 0) const SizedBox(width: 32),
                Expanded(child: f),
              ],
            ],
          )
        : _Stack(gap: 32, children: items);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BoardHeader(
          overline: 'Overlays & feedback',
          title: 'Dialogs, sheets, toasts',
          lead:
              'Confirm before anything that costs money, removes data or '
              'cancels work. Sheets for choices, toasts for quick results.',
        ),
        const SizedBox(height: 32),
        grid(frames),
        const SizedBox(height: 32),
        grid(feedback),
      ],
    );
  }
}

class _SortList extends StatefulWidget {
  const _SortList();

  @override
  State<_SortList> createState() => _SortListState();
}

class _SortListState extends State<_SortList> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) => _Bordered(
    child: KList(
      children: [
        for (final (i, label) in [
          'Most popular',
          'Newest',
          'Price: low to high',
        ].indexed)
          Semantics(
            inMutuallyExclusiveGroup: true,
            checked: i == _selected,
            child: KListRow(
              title: label,
              trailing: KRadioMark(selected: i == _selected),
              onTap: () => setState(() => _selected = i),
            ),
          ),
      ],
    ),
  );
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.caption,
    required this.detail,
    required this.child,
  });
  final String caption;
  final String detail;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: caption,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: detail),
            ],
          ),
          style: k.text.small.copyWith(color: k.colors.ink2),
        ),
      ],
    );
  }
}

/// 520 px phone-like frame: page skeleton, scrim, then the overlay.
class _Frame extends StatelessWidget {
  const _Frame({required this.background, required this.overlay});
  final Widget background;
  final Widget overlay;

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    return Container(
      height: 520,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(24),
      ),
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            background,
            const ColoredBox(color: KColors.scrim),
            overlay,
          ],
        ),
      ),
    );
  }
}

class _SkeletonPage extends StatelessWidget {
  const _SkeletonPage({this.cards = false, this.grid = false});
  final bool cards;
  final bool grid;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children;
    if (grid) {
      children = [
        for (var r = 0; r < 2; r++) ...[
          if (r > 0) const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(child: KSkeleton(height: 150, radius: 16)),
              SizedBox(width: 12),
              Expanded(child: KSkeleton(height: 150, radius: 16)),
            ],
          ),
        ],
      ];
    } else if (cards) {
      children = const [
        FractionallySizedBox(
          widthFactor: .4,
          alignment: Alignment.centerLeft,
          child: KSkeleton(height: 22),
        ),
        SizedBox(height: 14),
        KSkeleton(height: 90, radius: 16),
        SizedBox(height: 14),
        KSkeleton(height: 90, radius: 16),
        SizedBox(height: 14),
        KSkeleton(height: 90, radius: 16),
      ];
    } else {
      children = const [
        FractionallySizedBox(
          widthFactor: .5,
          alignment: Alignment.centerLeft,
          child: KSkeleton(height: 22),
        ),
        SizedBox(height: 14),
        KSkeleton(height: 220, radius: 16),
        SizedBox(height: 14),
        FractionallySizedBox(
          widthFactor: .7,
          alignment: Alignment.centerLeft,
          child: KSkeleton(height: 14),
        ),
        SizedBox(height: 14),
        FractionallySizedBox(
          widthFactor: .4,
          alignment: Alignment.centerLeft,
          child: KSkeleton(height: 14),
        ),
      ];
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
