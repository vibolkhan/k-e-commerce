/// "Why are you leaving?" on S-08f. Sent as [code] so the audit log reads
/// the same whatever language the person used.
enum DeleteReason {
  notUsing('not_using'),
  otherAccount('other_account'),
  privacy('privacy'),
  notifications('too_many_notifications'),
  other('other');

  const DeleteReason(this.code);

  final String code;
}
