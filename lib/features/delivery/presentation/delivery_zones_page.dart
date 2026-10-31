import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/ui/k_ui.dart';
import '../../admin/presentation/admin_pages.dart';
import '../data/delivery_repository.dart';
import '../domain/delivery.dart';
import 'delivery_map.dart';
import 'delivery_providers.dart';

String _usd(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

class DeliveryZonesPage extends ConsumerWidget {
  const DeliveryZonesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final value = ref.watch(deliveryZonesProvider);
    return AdminPage(
      title: l.deliveryZones,
      showBack: true,
      parent: AppRoutes.adminSettings,
      children: [
        if (isAdminWide(context)) ...[
          const SettingsNav(current: SettingsPage.zones),
          const SizedBox(height: 16),
        ],
        Text(
          l.deliveryZonesSubtitle,
          style: context.k.text.body.copyWith(color: context.k.colors.muted),
        ),
        const SizedBox(height: 16),
        value.when(
          loading: () => const Center(child: KSpinner(blue: true)),
          error: (_, _) => KEmptyState(
            icon: KIcons.delivery,
            title: l.deliveryZonesLoadFailed,
            action: KButton.tonal(
              label: l.deliveryRetry,
              onPressed: () => ref.invalidate(deliveryZonesProvider),
            ),
          ),
          data: (zones) => _ZonesBody(zones: zones),
        ),
      ],
    );
  }
}

class _ZonesBody extends ConsumerWidget {
  const _ZonesBody({required this.zones});
  final List<DeliveryZone> zones;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final k = context.k;
    if (zones.isEmpty) {
      return KEmptyState(icon: KIcons.delivery, title: l.deliveryZonesEmpty);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(KRadius.card),
          child: DeliveryMap(zones: zones, height: 320),
        ),
        const SizedBox(height: 8),
        Text(
          l.deliveryZoneMapHint,
          style: k.text.caption.copyWith(color: k.colors.muted),
        ),
        const SizedBox(height: 16),
        if (MediaQuery.sizeOf(context).width >= 900)
          KCard(
            padding: EdgeInsets.zero,
            clip: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  l.deliveryZoneName,
                  l.deliveryFee,
                  l.deliveryFreeOver,
                  l.deliverySameDay,
                  l.deliveryCod,
                  l.deliveryCodLimit,
                  l.deliveryStatus,
                  l.deliveryActions,
                ].map((label) => DataColumn(label: Text(label))).toList(),
                rows: [for (final zone in zones) _row(context, ref, zone)],
              ),
            ),
          )
        else
          for (final zone in zones) ...[
            _ZoneCard(zone: zone),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 16),
        KBanner(message: l.deliveryZoneCheckoutNote, icon: KIcons.info),
      ],
    );
  }

  DataRow _row(BuildContext context, WidgetRef ref, DeliveryZone zone) {
    final l = AppLocalizations.of(context);
    return DataRow(
      cells: [
        DataCell(Text(zone.name)),
        DataCell(Text(_usd(zone.feeCents))),
        DataCell(Text(_usd(zone.freeThresholdCents))),
        DataCell(Text(zone.sameDay ? l.deliveryOn : l.deliveryOff)),
        DataCell(Text(zone.codEnabled ? l.deliveryOn : l.deliveryOff)),
        DataCell(Text(_usd(zone.codLimitCents))),
        DataCell(Text(zone.active ? l.deliveryActive : l.deliveryPaused)),
        DataCell(
          KButton.outline(
            key: Key('edit-zone-${zone.id}'),
            label: l.deliveryEdit,
            size: KButtonSize.sm,
            onPressed: () => showZoneEditor(context, ref, zone),
          ),
        ),
      ],
    );
  }
}

class _ZoneCard extends ConsumerWidget {
  const _ZoneCard({required this.zone});
  final DeliveryZone zone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(zone.name, style: context.k.text.title)),
              Chip(
                label: Text(
                  zone.active ? l.deliveryActive : l.deliveryPaused,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${l.deliveryFee}: ${_usd(zone.feeCents)} · '
            '${l.deliveryFreeOver}: ${_usd(zone.freeThresholdCents)}',
          ),
          Text(
            '${l.deliverySameDay}: '
            '${zone.sameDay ? l.deliveryOn : l.deliveryOff} · '
            '${l.deliveryCod}: ${zone.codEnabled ? l.deliveryOn : l.deliveryOff}',
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: KButton.outline(
              label: l.deliveryEdit,
              size: KButtonSize.sm,
              onPressed: () => showZoneEditor(context, ref, zone),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showZoneEditor(
  BuildContext context,
  WidgetRef ref,
  DeliveryZone zone,
) => showDialog<void>(
  context: context,
  builder: (_) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 820),
      child: _ZoneEditor(zone: zone, ref: ref),
    ),
  ),
);

class _ZoneEditor extends StatefulWidget {
  const _ZoneEditor({required this.zone, required this.ref});
  final DeliveryZone zone;
  final WidgetRef ref;

  @override
  State<_ZoneEditor> createState() => _ZoneEditorState();
}

class _ZoneEditorState extends State<_ZoneEditor> {
  late final name = TextEditingController(text: widget.zone.name);
  late final fee = TextEditingController(
    text: (widget.zone.feeCents / 100).toStringAsFixed(2),
  );
  late final free = TextEditingController(
    text: (widget.zone.freeThresholdCents / 100).toStringAsFixed(2),
  );
  late final codLimit = TextEditingController(
    text: (widget.zone.codLimitCents / 100).toStringAsFixed(2),
  );
  late var draft = widget.zone;
  var saving = false;

  @override
  void dispose() {
    name.dispose();
    fee.dispose();
    free.dispose();
    codLimit.dispose();
    super.dispose();
  }

  int? _cents(String value) {
    final amount = double.tryParse(value.trim());
    return amount == null ? null : (amount * 100).round();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final f = _cents(fee.text);
    final t = _cents(free.text);
    final limit = _cents(codLimit.text);
    if (name.text.trim().isEmpty ||
        f == null ||
        t == null ||
        limit == null ||
        f < 0 ||
        t < 0 ||
        limit < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.deliveryZoneInvalid)));
      return;
    }
    setState(() => saving = true);
    try {
      draft = draft.copyWith(
        name: name.text.trim(),
        feeCents: f,
        freeThresholdCents: t,
        codLimitCents: limit,
      );
      await widget.ref.read(deliveryRepositoryProvider).saveZone(draft);
      widget.ref.invalidate(deliveryZonesProvider);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.deliveryZoneSaveFailed)));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.deliveryEditZone(widget.zone.name),
                  style: context.k.text.h2,
                ),
              ),
              KIconButton(
                icon: KIcons.close,
                label: l.uiClose,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: DeliveryMap(
                  zones: [draft],
                  editingZone: draft,
                  height: 240,
                  onZoneChanged: (rings) =>
                      setState(() => draft = draft.copyWith(rings: rings)),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l.deliveryZoneDragHint,
                style: context.k.text.caption.copyWith(
                  color: context.k.colors.muted,
                ),
              ),
              const SizedBox(height: 14),
              KTextField(
                key: const Key('zone-name'),
                label: l.deliveryZoneName,
                controller: name,
              ),
              const SizedBox(height: 14),
              KTextField(
                key: const Key('zone-fee'),
                label: l.deliveryFee,
                prefixText: r'$',
                controller: fee,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
              ),
              const SizedBox(height: 14),
              KTextField(
                label: l.deliveryFreeOver,
                prefixText: r'$',
                controller: free,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 10),
              KSwitchRow(
                label: l.deliverySameDay,
                value: draft.sameDay,
                onChanged: (v) =>
                    setState(() => draft = draft.copyWith(sameDay: v)),
              ),
              KSwitchRow(
                label: l.deliveryCod,
                value: draft.codEnabled,
                onChanged: (v) =>
                    setState(() => draft = draft.copyWith(codEnabled: v)),
              ),
              KTextField(
                label: l.deliveryCodLimit,
                prefixText: r'$',
                controller: codLimit,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                helpText: l.deliveryCodLimitHelp,
              ),
              const SizedBox(height: 8),
              KSwitchRow(
                label: l.deliveryZoneActive,
                value: draft.active,
                onChanged: (v) =>
                    setState(() => draft = draft.copyWith(active: v)),
              ),
              const SizedBox(height: 12),
              KBanner(message: l.deliveryZoneChangesNote, icon: KIcons.info),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              KButton.outline(
                label: l.uiCancel,
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 12),
              KButton(
                key: const Key('save-zone'),
                label: l.deliverySaveZone,
                loading: saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
