/// Route paths. Feature routes are added here as features land.
abstract final class AppRoutes {
  static const root = '/';
  static const loading = '/loading';
  static const forbidden = '/forbidden';
  static const customer = '/customer';
  static const business = '/business';
  static const rider = '/rider';
  static const admin = '/admin';

  /// Every K component; dev and staging builds only, not linked anywhere.
  static const designGallery = '/design-gallery';
}
