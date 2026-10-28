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

  /// F08 back-office. Each `AdminSection` lives under `/admin/<segment>`;
  /// More (M-05) and the pending-invite page are open to every staff member.
  static String adminSection(String segment) =>
      segment.isEmpty ? admin : '$admin/$segment';
  static const adminMore = '$admin/more';
  static const adminPending = '$admin/pending';
  static const adminStaff = '$admin/settings/staff';

  /// F09 catalogue (A-05 – A-05e). Creating and importing are for roles
  /// that may edit products; everyone who sees the section can open a
  /// product read-only.
  static const adminCatalog = '$admin/catalog';
  static const adminProductNew = '$adminCatalog/new';
  static const adminCatalogImport = '$adminCatalog/import';
  static String adminProduct(String id) => '$adminCatalog/$id';

  /// F10 A-06 Inventory.
  static const adminInventory = '$admin/inventory';

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

  /// Staff invited by email set a password once after the link signs them in.
  static const signInSetPassword = '/sign-in/set-password';

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

  /// F11 browsing, inside the customer and business shells: C-02 and C-03
  /// (a category or a collection); F12 search (C-04, `?q=` opens on the
  /// results); F13 product detail (C-05; B-00a for business buyers is a
  /// placeholder until F26). The cart (C-06, F16) and the business upgrade
  /// (B-01) are placeholders until their tasks land.
  static String categories(String shell) => '$shell/categories';
  static String category(String shell, String slug) =>
      '$shell/categories/$slug';
  static String collection(String shell, String slug) =>
      '$shell/collections/$slug';
  static String search(String shell, {String? query}) => query == null
      ? '$shell/search'
      : Uri(path: '$shell/search', queryParameters: {'q': query}).toString();
  static String product(String shell, String id) => '$shell/products/$id';
  static String cart(String shell) => '$shell/cart';
  static String businessUpgrade(String shell) => '$shell/business-upgrade';

  /// Every K component; dev and staging builds only, not linked anywhere.
  static const designGallery = '/design-gallery';
}
