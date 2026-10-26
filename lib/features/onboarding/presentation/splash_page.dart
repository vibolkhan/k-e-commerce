import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/k_ui.dart';

/// S-01: the K mark on brand sky while the saved session and profile load.
/// The router leaves this page by itself once they have.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: KColors.sky500,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const KLogo.white(size: 96),
            const SizedBox(height: 44),
            Semantics(
              liveRegion: true,
              label: l10n.uiLoading,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Dot(opacity: 1),
                  SizedBox(width: 8),
                  _Dot(opacity: .65),
                  SizedBox(width: 8),
                  _Dot(opacity: .35),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}
