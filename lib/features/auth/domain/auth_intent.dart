/// Why sign-in was asked for (App Flow F1 trigger). After signing in the
/// person goes back to that action with its state kept.
enum AuthIntent {
  checkout,
  rfq,
  wishlist,
  review,
  chat,

  /// Account › Sign in: no action to resume.
  account;

  static AuthIntent? tryParse(String? value) {
    for (final intent in values) {
      if (intent.name == value) return intent;
    }
    return null;
  }
}
