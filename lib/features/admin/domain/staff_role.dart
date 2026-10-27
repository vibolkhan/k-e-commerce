/// `staff_role` in the database: what a staff member can open and change
/// (A-14d). Super admins can do everything.
enum StaffRole {
  superAdmin('super_admin'),
  sales('sales'),
  support('support'),
  catalog('catalog');

  const StaffRole(this.dbName);

  final String dbName;

  static StaffRole? fromDb(String? value) {
    for (final role in values) {
      if (role.dbName == value) return role;
    }
    return null;
  }
}

/// `staff_members.status`. Only active staff have rights; an invite turns
/// active on the first sign-in within 7 days.
enum StaffStatus {
  active,
  invited,
  removed;

  static StaffStatus? fromDb(String? value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }
}
