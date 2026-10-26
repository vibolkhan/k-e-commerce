/// What `account-delete` answered (AUTH-07).
sealed class DeleteAccountOutcome {
  const DeleteAccountOutcome();
}

/// Personal data is gone and every session is revoked; sign out locally.
class AccountDeleted extends DeleteAccountOutcome {
  const AccountDeleted();
}

/// An order or return is still in progress; nothing was deleted.
class HasActiveOrders extends DeleteAccountOutcome {
  const HasActiveOrders();
}

/// Riders and staff are removed by an admin, not from the app.
class DeleteNotAllowed extends DeleteAccountOutcome {
  const DeleteNotAllowed();
}

/// Network or server error; nothing was deleted.
class DeleteFailed extends DeleteAccountOutcome {
  const DeleteFailed(this.error);
  final Object error;
}
