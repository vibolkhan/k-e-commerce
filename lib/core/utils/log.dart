import 'package:flutter/foundation.dart';

/// App logger. Use instead of `print` (enforced by the `avoid_print` lint).
void log(String message) {
  if (kDebugMode) debugPrint('[K] $message');
}
