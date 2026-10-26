/// Route paths. Feature routes are added here as features land.
abstract final class AppRoutes {
  static const root = '/';
  static const loading = '/loading';
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

  /// Every K component; dev and staging builds only, not linked anywhere.
  static const designGallery = '/design-gallery';
}
