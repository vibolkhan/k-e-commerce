@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/features/design_gallery/presentation/design_gallery_page.dart';

import '../../helpers.dart';

void main() {
  testWidgets('gallery matches the boards at 1440 px', (tester) async {
    setViewSize(tester, const Size(1440, 5200));
    await withRealShadows(() async {
      await tester.pumpWidget(localized(const DesignGalleryPage()));
      // Spinners never settle; a fixed pump keeps the frame deterministic.
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byType(DesignGalleryPage),
        matchesGoldenFile('goldens/design_gallery_1440.png'),
      );
    });
  });
}
