import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/k_ui.dart';

/// CAT-01: staff can scan a variant's barcode with the camera. The scanner
/// works on phones, the web and macOS; elsewhere the field stays typed.
bool cameraScanSupported(TargetPlatform platform) =>
    kIsWeb ||
    platform == TargetPlatform.android ||
    platform == TargetPlatform.iOS ||
    platform == TargetPlatform.macOS;

/// Opens the camera and returns the first barcode read, or null.
Future<String?> scanBarcode(BuildContext context) => showKBottomSheet<String>(
  context,
  title: AppLocalizations.of(context).catalogScanTitle,
  builder: (_) => const _ScanView(),
);

class _ScanView extends StatefulWidget {
  const _ScanView();

  @override
  State<_ScanView> createState() => _ScanViewState();
}

class _ScanViewState extends State<_ScanView> {
  var _done = false;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.catalogScanHint, style: k.text.body),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(KRadius.card),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: MobileScanner(
                onDetect: _onDetect,
                errorBuilder: (context, _) => ColoredBox(
                  color: k.colors.soft,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.catalogScanUnavailable,
                        textAlign: TextAlign.center,
                        style: k.text.body,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
