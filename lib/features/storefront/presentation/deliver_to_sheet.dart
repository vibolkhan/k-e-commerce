import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/k_ui.dart';
import '../../auth/domain/auth_intent.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/require_sign_in.dart';
import 'storefront_providers.dart';

/// "Deliver to" from the home pill: pick one of the saved addresses for this
/// session. Guests are asked to sign in; adding and editing addresses comes
/// with checkout (C-07).
Future<void> showDeliverToSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showKBottomSheet<void>(
    context,
    title: l10n.storeDeliverToTitle,
    builder: (_) => const _DeliverToBody(),
  );
}

class _DeliverToBody extends ConsumerWidget {
  const _DeliverToBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final signedIn = ref.watch(currentProfileProvider).value != null;
    final viewer = watchViewer(ref);
    final addresses = ref.watch(savedAddressesProvider(viewer));
    final current = ref.watch(deliverToProvider(viewer));
    if (!signedIn) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.storeDeliverToGuest,
            style: k.text.body.copyWith(color: k.colors.ink2),
          ),
          const SizedBox(height: 16),
          KButton(
            label: l10n.storeDeliverToSignIn,
            expand: true,
            onPressed: () async {
              final navigator = Navigator.of(context);
              if (await requireSignIn(context, ref, AuthIntent.account)) {
                await navigator.maybePop();
              }
            },
          ),
        ],
      );
    }
    final list = addresses.value ?? const [];
    if (addresses.isLoading && !addresses.hasValue) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: KSpinner(blue: true)),
      );
    }
    if (list.isEmpty) {
      return Text(
        l10n.storeDeliverToNone,
        style: k.text.body.copyWith(color: k.colors.ink2),
      );
    }
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in list) ...[
            KOptionTile(
              title: a.label,
              subtitle: a.area ?? l10n.storeOutsideZone,
              icon: KIcons.location,
              selected: a.id == current?.id,
              onTap: () {
                ref.read(deliverToChoiceProvider.notifier).pick(a.id);
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
