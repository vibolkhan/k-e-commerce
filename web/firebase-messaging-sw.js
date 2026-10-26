// F07 · Web push (NOT-01). FCM shows notifications from here while the tab
// is closed or in the background, and a tap opens the link the notify Edge
// Function sets (fcm_options.link → /#/<route>). While the app is open, FCM
// hands the message to the page instead, which shows the in-app banner.
//
// The project config is per environment, so it lives in firebase-config.js,
// written by `dart run tool/web_push_config.dart` from config/env.json and
// never committed. Without it this worker does nothing and web push is off.
try {
  importScripts('firebase-config.js');
} catch (_) {
  // Not configured.
}

if (self.K_FIREBASE_CONFIG) {
  // Same Firebase JS SDK version the app loads (firebase_core_web).
  importScripts(
    'https://www.gstatic.com/firebasejs/13.1.0/firebase-app-compat.js',
    'https://www.gstatic.com/firebasejs/13.1.0/firebase-messaging-compat.js',
  );
  firebase.initializeApp(self.K_FIREBASE_CONFIG);
  firebase.messaging();
}
