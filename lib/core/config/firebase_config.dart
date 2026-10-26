import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase project for push (NOT-01). Each platform registers its own app
/// in the Firebase console, so each has its own app id and API key. Values
/// come from `--dart-define-from-file`, like the Supabase keys; empty means
/// push is off on that platform and the inbox still works.
class FirebaseConfig {
  const FirebaseConfig({
    this.projectId = '',
    this.messagingSenderId = '',
    this.androidAppId = '',
    this.androidApiKey = '',
    this.iosAppId = '',
    this.iosApiKey = '',
    this.webAppId = '',
    this.webApiKey = '',
    this.webVapidKey = '',
  });

  factory FirebaseConfig.fromEnvironment() => const FirebaseConfig(
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
    messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
    androidAppId: String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
    androidApiKey: String.fromEnvironment('FIREBASE_ANDROID_API_KEY'),
    iosAppId: String.fromEnvironment('FIREBASE_IOS_APP_ID'),
    iosApiKey: String.fromEnvironment('FIREBASE_IOS_API_KEY'),
    webAppId: String.fromEnvironment('FIREBASE_WEB_APP_ID'),
    webApiKey: String.fromEnvironment('FIREBASE_WEB_API_KEY'),
    webVapidKey: String.fromEnvironment('FIREBASE_WEB_VAPID_KEY'),
  );

  final String projectId;
  final String messagingSenderId;
  final String androidAppId;
  final String androidApiKey;
  final String iosAppId;
  final String iosApiKey;
  final String webAppId;
  final String webApiKey;

  /// Web Push certificate (Cloud Messaging › Web configuration).
  final String webVapidKey;

  /// Options for the platform this build runs on; null when not configured.
  FirebaseOptions? optionsFor(TargetPlatform platform, {required bool web}) {
    final (appId, apiKey) = web
        ? (webAppId, webApiKey)
        : switch (platform) {
            TargetPlatform.android => (androidAppId, androidApiKey),
            TargetPlatform.iOS => (iosAppId, iosApiKey),
            _ => ('', ''),
          };
    if (projectId.isEmpty ||
        messagingSenderId.isEmpty ||
        appId.isEmpty ||
        apiKey.isEmpty ||
        (web && webVapidKey.isEmpty)) {
      return null;
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
    );
  }

  FirebaseOptions? get currentOptions =>
      optionsFor(defaultTargetPlatform, web: kIsWeb);
}
