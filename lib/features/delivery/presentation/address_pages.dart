import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/ui/k_ui.dart';
import '../data/delivery_repository.dart';
import '../domain/delivery.dart';
import 'delivery_map.dart';
import 'delivery_providers.dart';

class AddressListPage extends ConsumerWidget {
  const AddressListPage({super.key, required this.shell});
  final String shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final value = ref.watch(addressesProvider);
    return Scaffold(
      appBar: KAppBar(title: l.deliveryAddresses, line: true),
      body: value.when(
        loading: () => const Center(child: KSpinner(blue: true)),
        error: (_, _) => KEmptyState(
          icon: KIcons.location,
          title: l.deliveryAddressLoadFailed,
          action: KButton.tonal(
            label: l.deliveryRetry,
            onPressed: () => ref.invalidate(addressesProvider),
          ),
        ),
        data: (addresses) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (addresses.isEmpty)
              KEmptyState(
                icon: KIcons.location,
                title: l.deliveryAddressEmpty,
                message: l.deliveryAddressEmptyBody,
              ),
            for (final address in addresses) ...[
              _AddressCard(address: address, shell: shell),
              const SizedBox(height: 12),
            ],
            KButton.tonal(
              key: const Key('add-address'),
              label: l.deliveryAddAddress,
              icon: KIcons.plus,
              expand: true,
              onPressed: () => context.push(AppRoutes.addressNew(shell)),
            ),
            const SizedBox(height: 12),
            Text(
              l.deliveryCoverageNote,
              textAlign: TextAlign.center,
              style: context.k.text.caption.copyWith(color: context.k.colors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressCard extends ConsumerWidget {
  const _AddressCard({required this.address, required this.shell});
  final DeliveryAddress address;
  final String shell;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: KConfirmDialog(
          title: l.deliveryDeleteTitle(address.label),
          message: l.deliveryDeleteBody(address.line),
          confirmLabel: l.deliveryDelete,
          cancelLabel: l.deliveryKeep,
          tone: KConfirmTone.destructive,
          onCancel: () => Navigator.pop(dialogContext, false),
          onConfirm: () => Navigator.pop(dialogContext, true),
        ),
      ),
    );
    if (confirmed != true) return;
    await ref.read(deliveryRepositoryProvider).deleteAddress(address.id);
    ref.invalidate(addressesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final k = context.k;
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: k.colors.tint2, borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: KIcon(KIcons.location, color: k.colors.primaryInk),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(address.label, style: k.text.body.copyWith(fontWeight: FontWeight.w700)),
                      if (address.isDefault) Chip(label: Text(l.deliveryDefault), visualDensity: VisualDensity.compact),
                    ]),
                    const SizedBox(height: 3),
                    Text(address.displayLine, style: k.text.small.copyWith(color: k.colors.ink2)),
                    if (address.recipientName != null || address.phone != null)
                      Text(
                        [address.recipientName, address.phone].whereType<String>().join(' · '),
                        style: k.text.small.copyWith(color: k.colors.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            KButton.outline(
              key: Key('edit-${address.id}'),
              label: l.deliveryEdit,
              size: KButtonSize.sm,
              onPressed: () => context.push(AppRoutes.addressEdit(shell, address.id)),
            ),
            KButton.ghost(
              key: Key('delete-${address.id}'),
              label: l.deliveryDelete,
              size: KButtonSize.sm,
              onPressed: () => _delete(context, ref),
            ),
            if (!address.isDefault)
              KButton.ghost(
                key: Key('default-${address.id}'),
                label: l.deliverySetDefault,
                size: KButtonSize.sm,
                onPressed: () async {
                  await ref.read(deliveryRepositoryProvider).setDefault(address.id);
                  ref.invalidate(addressesProvider);
                },
              ),
          ]),
        ],
      ),
    );
  }
}

class AddressEditorPage extends ConsumerStatefulWidget {
  const AddressEditorPage({super.key, this.id});
  final String? id;

  @override
  ConsumerState<AddressEditorPage> createState() => _AddressEditorPageState();
}

class _AddressEditorPageState extends ConsumerState<AddressEditorPage> {
  final line = TextEditingController();
  final note = TextEditingController();
  final name = TextEditingController();
  final phone = TextEditingController();
  var label = 'Home';
  var isDefault = false;
  var pin = const GeoPoint(11.576, 104.906);
  var saving = false;
  var locating = false;
  var loaded = false;

  @override
  void dispose() {
    line.dispose(); note.dispose(); name.dispose(); phone.dispose();
    super.dispose();
  }

  void _load(List<DeliveryAddress> addresses) {
    if (loaded || widget.id == null) return;
    final matches = addresses.where((a) => a.id == widget.id);
    if (matches.isEmpty) return;
    final a = matches.first;
    loaded = true;
    line.text = a.line; note.text = a.note ?? ''; name.text = a.recipientName ?? '';
    phone.text = a.phone?.replaceFirst('+855', '') ?? '';
    label = a.label; isDefault = a.isDefault; pin = a.point;
  }

  Future<void> _locate() async {
    final l = AppLocalizations.of(context);
    setState(() => locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw StateError('denied');
      }
      final position = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => pin = GeoPoint(position.latitude, position.longitude));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.deliveryLocationFailed)));
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    if (line.text.trim().isEmpty || name.text.trim().isEmpty || phone.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.fieldRequired)));
      return;
    }
    setState(() => saving = true);
    try {
      await ref.read(deliveryRepositoryProvider).saveAddress(AddressDraft(
        id: widget.id,
        label: label,
        line: line.text.trim(),
        city: 'Phnom Penh',
        point: pin,
        recipientName: name.text.trim(),
        phone: '+855${phone.text.replaceAll(RegExp(r'\D'), '')}',
        note: note.text.trim().isEmpty ? null : note.text.trim(),
        isDefault: isDefault,
      ));
      ref.invalidate(addressesProvider);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.deliverySaveFailed)));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    _load(ref.watch(addressesProvider).value ?? const []);
    return Scaffold(
      appBar: KAppBar(title: widget.id == null ? l.deliveryAddAddress : l.deliveryEditAddress, line: true),
      body: ListView(
        children: [
          Stack(children: [
            DeliveryMap(pin: pin, onPinChanged: (v) => setState(() => pin = v)),
            Positioned(
              right: 12, bottom: 12,
              child: KButton.tonal(
                key: const Key('current-location'),
                label: l.deliveryCurrentLocation,
                icon: KIcons.location,
                loading: locating,
                size: KButtonSize.sm,
                onPressed: _locate,
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(l.deliveryLabel, style: context.k.text.label),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final item in ['Home', 'Office', 'Other'])
                  ChoiceChip(
                    key: Key('label-${item.toLowerCase()}'),
                    label: Text(switch (item) { 'Home' => l.deliveryHome, 'Office' => l.deliveryOffice, _ => l.deliveryOther }),
                    selected: label == item,
                    onSelected: (_) => setState(() => label = item),
                  ),
              ]),
              const SizedBox(height: 14),
              KTextField(key: const Key('address-line'), controller: line, label: l.deliveryStreet),
              const SizedBox(height: 14),
              KTextField(controller: note, label: l.deliveryLandmark, optional: true),
              const SizedBox(height: 14),
              KTextField(key: const Key('address-name'), controller: name, label: l.deliveryRecipient),
              const SizedBox(height: 14),
              KTextField(key: const Key('address-phone'), controller: phone, label: l.deliveryPhone, prefixText: '+855', keyboardType: TextInputType.phone),
              const SizedBox(height: 10),
              KSwitchRow(label: l.deliverySetDefaultAddress, value: isDefault, onChanged: (v) => setState(() => isDefault = v)),
              const SizedBox(height: 18),
              KButton(
                key: const Key('save-address'),
                label: l.deliverySaveAddress,
                loading: saving,
                expand: true,
                onPressed: _save,
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

Future<void> showOutOfZoneDialog(BuildContext context, {String? area}) {
  final l = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const KIcon(KIcons.location, size: 28),
      title: Text(l.deliveryOutOfZoneTitle),
      content: Text(l.deliveryOutOfZoneBody(area ?? l.deliveryUnknownArea)),
      actions: [
        KButton.outline(label: l.deliverySeeAreas, onPressed: () => Navigator.pop(dialogContext)),
        KButton(label: l.deliveryChangeAddress, onPressed: () => Navigator.pop(dialogContext)),
      ],
    ),
  );
}
