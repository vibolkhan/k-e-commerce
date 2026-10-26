/// Route paths. Feature routes are added here as features land.
abstract final class AppRoutes {
  static const root = '/';
  static const loading = '/loading';

  /// F0 launch: S-01, then S-02 and S-03 on first launch only. [from] is a
  /// deep link to open once launch is done.
  static const splash = '/splash';
  static const welcomeLanguage = '/welcome/language';
  static const welcomeIntro = '/welcome/intro';

  static bool isLaunch(String path) =>
      path == root || path == splash || path.startsWith('/welcome/');

  static String launchStep(String path, {String? from}) => Uri(
    path: path,
    queryParameters: {'from': ?from},
  ).toString().replaceFirst(RegExp(r'\?$'), '');
  static const forbidden = '/forbidden';
  static const customer = '/customer';
  static const business = '/business';
  static const rider = '/rider';
  static const admin = '/admin';

  /// F05 sign-in flow: S-04 → S-05 → S-06.
  static const signIn = '/sign-in';
  static const signInVerify = '/sign-in/verify';
  static const signInProfile = '/sign-in/profile';

  /// S-04 for [intent] (an `AuthIntent` name). [from] is where to land when
  /// the flow can't simply pop back (cold start, web reload); [blocked]
  /// opens S-06b on arrival.
  static String signInFor({
    String? intent,
    String? from,
    bool blocked = false,
  }) => Uri(
    path: signIn,
    queryParameters: {
      'intent': ?intent,
      'from': ?from,
      if (blocked) 'blocked': '1',
    },
  ).toString().replaceFirst(RegExp(r'\?$'), '');

  static String signInVerifyFor(String phone) =>
      Uri(path: signInVerify, queryParameters: {'phone': phone}).toString();

  static bool isSignInFlow(String path) =>
      path == signIn || path.startsWith('$signIn/');

  /// S-08 family, inside the customer and business shells.
  static String account(String shell) => '$shell/account';
  static String accountEdit(String shell) => '$shell/account/edit';
  static String accountDelete(String shell) => '$shell/account/delete';

  /// S-08d.
  static String accountNotifications(String shell) =>
      '$shell/account/notifications';

  /// F07 S-07 inbox, and the screens notifications open. Order (C-12),
  /// quote (B-05) and chat (C-17) are placeholders until their tasks land;
  /// the paths are final because pushes already link to them.
  static String inbox(String shell) => '$shell/inbox';
  static String order(String shell, String id) => '$shell/orders/$id';
  static String quote(String id) => '$business/quotes/$id';
  static String chat(String shell, String id) => '$shell/chat/$id';

  /// Every K component; dev and staging builds only, not linked anywhere.
  static const designGallery = '/design-gallery';
}
