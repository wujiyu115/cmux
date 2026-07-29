import '../utils/team/team_member_naming.dart';
import 'team_roster_slot.dart';

/// Default roster slots for a newly created team (leader + developer + reviewer).
abstract final class DefaultTeamRoster {
  static const developerMemberId = 'developer';
  static const reviewerMemberId = 'reviewer';

  /// Canonical key prefix for rosters shipped inside the app.
  static const builtinKeyPrefix = 'teampilot/builtin';

  static String expertKeyForSlug(String slug) => '$builtinKeyPrefix/$slug';

  static List<TeamRosterSlot> bootstrap({int? joinedAt}) {
    final ts = joinedAt ?? DateTime.now().millisecondsSinceEpoch;
    return [
      TeamRosterSlot(
        id: TeamMemberNaming.teamLeadName,
        expertKey: expertKeyForSlug('team-lead'),
        joinedAt: ts,
      ),
      TeamRosterSlot(
        id: developerMemberId,
        expertKey: expertKeyForSlug('developer'),
        joinedAt: ts,
      ),
      TeamRosterSlot(
        id: reviewerMemberId,
        expertKey: expertKeyForSlug('reviewer'),
        joinedAt: ts,
      ),
    ];
  }
}
