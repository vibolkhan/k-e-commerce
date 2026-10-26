import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled fonts so widget tests and goldens render real text, and
/// lets goldens differ by a hair (anti-aliasing varies between machines).
/// Goldens are made on Windows and tagged `golden`; CI skips them.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadFonts();
  final comparator = goldenFileComparator;
  if (comparator is LocalFileComparator) {
    goldenFileComparator = _TolerantComparator(
      comparator.basedir.resolve('flutter_test_config.dart'),
    );
  }
  await testMain();
}

const _fonts = {
  'PlusJakartaSans': [400, 500, 600, 700, 800],
  'KantumruyPro': [400, 500, 600, 700],
};

Future<void> _loadFonts() async {
  for (final MapEntry(key: family, value: weights) in _fonts.entries) {
    final loader = FontLoader(family);
    for (final w in weights) {
      loader.addFont(rootBundle.load('assets/fonts/$family-$w.ttf'));
    }
    await loader.load();
  }
}

class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);

  /// Max share of differing pixels (0.5 %).
  static const _tolerance = 0.005;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= _tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
