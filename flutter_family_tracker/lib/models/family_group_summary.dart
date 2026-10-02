class FamilyGroupSummary {
  final String familyName;
  final String displayName;
  final int memberCount;
  final String? adminName;
  final bool isUserMember;
  final bool isUserAdmin;
  final List<String> memberNames;
  final String searchIndex;

  FamilyGroupSummary({
    required this.familyName,
    required this.displayName,
    required this.memberCount,
    this.adminName,
    required this.isUserMember,
    this.isUserAdmin = false,
    this.memberNames = const [],
    String? searchIndex,
  }) : searchIndex = searchIndex ??
            '$familyName $displayName ${adminName ?? ""} ${memberNames.join(" ")}'.toLowerCase();

  @pragma('vm:prefer-inline')
  bool matchesQuery(String queryLower) {
    if (queryLower.isEmpty) return true;
    return searchIndex.contains(queryLower);
  }
}
