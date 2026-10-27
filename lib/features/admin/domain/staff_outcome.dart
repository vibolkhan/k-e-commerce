/// Answers from the staff-manage Edge Function (`_shared/staff_flows.ts`).
sealed class StaffOutcome {
  const StaffOutcome();

  static StaffOutcome fromJson(Map<String, dynamic> json) =>
      switch (json['status']) {
        'invited' => const StaffDone(StaffAction.invited),
        'resent' => const StaffDone(StaffAction.resent),
        'updated' => const StaffDone(StaffAction.updated),
        'removed' => const StaffDone(StaffAction.removed),
        'invalid' => StaffInvalid(switch (json['field']) {
          'full_name' => StaffField.fullName,
          'contact' => StaffField.contact,
          _ => StaffField.role,
        }),
        final String status => StaffRefused(
          StaffRefusal.values.firstWhere(
            (r) => r.wire == status,
            orElse: () => StaffRefusal.unknown,
          ),
        ),
        _ => const StaffRefused(StaffRefusal.unknown),
      };
}

enum StaffAction { invited, resent, updated, removed }

enum StaffField { fullName, contact, role }

enum StaffRefusal {
  forbidden('forbidden'),
  accountExists('account_exists'),
  alreadyStaff('already_staff'),
  notFound('not_found'),
  notInvited('not_invited'),
  self('self'),
  lastSuperAdmin('last_super_admin'),
  sendFailed('send_failed'),

  /// Offline, a server error or an answer this build doesn't know.
  unknown('');

  const StaffRefusal(this.wire);

  final String wire;
}

class StaffDone extends StaffOutcome {
  const StaffDone(this.action);
  final StaffAction action;
}

class StaffInvalid extends StaffOutcome {
  const StaffInvalid(this.field);
  final StaffField field;
}

class StaffRefused extends StaffOutcome {
  const StaffRefused(this.reason);
  final StaffRefusal reason;
}
