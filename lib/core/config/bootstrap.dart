import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/log.dart';
import 'app_config.dart';

/// Overridden in `main.dart` with the config read at startup.
final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

/// Initialises backend services. Supabase is skipped when it isn't configured
/// so the shell (and tests) run without keys; Firebase (push) likewise.
Future<void> bootstrap(AppConfig config) async {
  if (!config.isSupabaseConfigured) {
    if (config.isProd) {
      throw StateError(
        'SUPABASE_URL and SUPABASE_ANON_KEY are required in prod',
      );
    }
    log('Supabase not configured (${config.env.name}); running offline');
    return;
  }
  await Supabase.initialize(
    url: config.supabaseUrl,
    publishableKey: config.supabaseAnonKey,
  );
  await _initFirebase(config);
}

/// Push is optional: a missing or broken Firebase setup never stops the app.
Future<void> _initFirebase(AppConfig config) async {
  final options = config.firebase.currentOptions;
  if (options == null) {
    log('Firebase not configured for this platform; push is off');
    return;
  }
  try {
    await Firebase.initializeApp(options: options);
  } catch (e) {
    log('Firebase failed to start; push is off: $e');
  }
}
