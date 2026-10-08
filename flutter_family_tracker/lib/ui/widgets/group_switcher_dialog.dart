import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../models/family_group_summary.dart';
import '../../providers/family_provider.dart';

class GroupSwitcherDialog extends StatefulWidget {
  final String currentGroup;
  final List<String> availableGroups;
  final Function(String newGroup) onSwitch;

  const GroupSwitcherDialog({
    super.key,
    required this.currentGroup,
    this.availableGroups = const [],
    required this.onSwitch,
  });

  @override
  State<GroupSwitcherDialog> createState() => _GroupSwitcherDialogState();
}

class _GroupSwitcherDialogState extends State<GroupSwitcherDialog> {
  final _searchController = TextEditingController();
  final _customNameController = TextEditingController();

  List<FamilyGroupSummary> _allFamilies = [];
  List<FamilyGroupSummary> _filteredFamilies = [];
  bool _isLoading = true;
  String _selectedTab = 'all'; // 'all', 'admin'
  bool _showCustomInput = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    // Instantly seed with availableGroups without showing loading indicator
    if (widget.availableGroups.isNotEmpty) {
      _isLoading = false;
      _allFamilies = widget.availableGroups.map((g) {
        return FamilyGroupSummary(
          familyName: g,
          displayName: FamilyProvider.formatFamilyDisplayName(g),
          memberCount: 1,
          isUserMember: true,
        );
      }).toList();
      _recomputeFiltered();
    }
    _loadFamilySummaries();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _customNameController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _recomputeFiltered();
    });
  }

  void _recomputeFiltered() {
    final query = _searchController.text.trim().toLowerCase();
    _filteredFamilies = _allFamilies.where((f) {
      if (_selectedTab == 'admin' && !f.isUserAdmin) return false;
      if (query.isEmpty) return true;
      return f.matchesQuery(query);
    }).toList();
  }

  void _setTab(String tabKey) {
    if (_selectedTab == tabKey) return;
    setState(() {
      _selectedTab = tabKey;
      _recomputeFiltered();
    });
  }

  Future<void> _loadFamilySummaries() async {
    try {
      final familyProvider = Provider.of<FamilyProvider>(context, listen: false);
      final list = await familyProvider
          .fetchAvailableFamilies()
          .timeout(const Duration(seconds: 4), onTimeout: () => []);
      if (mounted) {
        setState(() {
          if (list.isNotEmpty) {
            _allFamilies = list;
          }
          _recomputeFiltered();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _switchGroup(String familyName) {
    final clean = familyName.trim();
    if (clean.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    widget.onSwitch(clean);
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Switched to ${FamilyProvider.formatFamilyDisplayName(clean)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredFamilies;
    final query = _searchController.text.trim();
    final queryLower = query.toLowerCase();
    final bool exactMatchExists = queryLower.isNotEmpty && _allFamilies.any(
      (f) => f.familyName.toLowerCase() == queryLower ||
             f.displayName.toLowerCase() == queryLower,
    );

    final int adminCount = _allFamilies.where((f) => f.isUserAdmin).length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.white,
      elevation: 12,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 480,
          maxHeight: 650,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with Gradient Banner
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.family_restroom_rounded,
                      color: AppColors.textWhite,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Switch Family Circle',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textWhite,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Select from your joined family circles',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFFE0E7FF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textWhite),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            // Search Bar Input
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.bgSurfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.cardBorder, width: 1.2),
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: 'Search your family circles or members...',
                    hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.cancel_rounded, color: AppColors.textMuted, size: 20),
                            onPressed: () => _searchController.clear(),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
                  ),
                ),
              ),
            ),

            // Category Filter Chips
            if (adminCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    _buildFilterChip(
                      label: 'All My Circles (${_allFamilies.length})',
                      tabKey: 'all',
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      label: 'Admin Of ($adminCount)',
                      tabKey: 'admin',
                    ),
                  ],
                ),
              ),

            // Loading bar if fetching fresh list
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(
                  minHeight: 2.5,
                  backgroundColor: AppColors.bgSurfaceElevated,
                  color: AppColors.primary,
                ),
              ),

            const Divider(height: 12, thickness: 1, color: AppColors.cardBorder),

            // Families List
            Expanded(
              child: filtered.isEmpty
                  ? _buildEmptyState(query)
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final fam = filtered[index];
                        final bool isCurrent =
                            fam.familyName.toLowerCase() == widget.currentGroup.toLowerCase();

                        return _buildFamilyCard(fam, isCurrent);
                      },
                    ),
            ),

            // Bottom Action: Create / Custom Family Toggle
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: AppColors.bgSurfaceElevated,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                border: Border(top: BorderSide(color: AppColors.cardBorder)),
              ),
              child: _showCustomInput
                  ? Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: TextField(
                              controller: _customNameController,
                              autofocus: true,
                              decoration: const InputDecoration(
                                hintText: 'Enter new family name...',
                                hintStyle: TextStyle(fontSize: 13, color: AppColors.textMuted),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                              onSubmitted: (val) => _switchGroup(val),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _switchGroup(_customNameController.text),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Join / Switch', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                          onPressed: () => setState(() => _showCustomInput = false),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (query.isNotEmpty && !exactMatchExists)
                          Expanded(
                            child: InkWell(
                              onTap: () => _switchGroup(query),
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.add_circle_outline_rounded,
                                        size: 20, color: AppColors.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Join/Create "$query"',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else
                          Text(
                            'Active: ${FamilyProvider.formatFamilyDisplayName(widget.currentGroup)}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        TextButton.icon(
                          onPressed: () => setState(() => _showCustomInput = true),
                          icon: const Icon(Icons.edit_note_rounded, size: 18),
                          label: const Text('Custom Name', style: TextStyle(fontSize: 13)),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({required String label, required String tabKey}) {
    final isSelected = _selectedTab == tabKey;
    return InkWell(
      onTap: () => _setTab(tabKey),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.bgSurfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildFamilyCard(FamilyGroupSummary fam, bool isCurrent) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _switchGroup(fam.familyName),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isCurrent
                ? AppColors.primary.withValues(alpha: 0.08)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isCurrent
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : AppColors.cardBorder,
              width: isCurrent ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: isCurrent
                      ? AppColors.primaryGradient
                      : LinearGradient(
                          colors: [
                            AppColors.primaryLight.withValues(alpha: 0.3),
                            AppColors.accent.withValues(alpha: 0.3),
                          ],
                        ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    fam.displayName.isNotEmpty
                        ? fam.displayName.substring(0, 1).toUpperCase()
                        : 'F',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isCurrent ? Colors.white : AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Title and details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            fam.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                              color: isCurrent ? AppColors.primary : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                        if (fam.isUserAdmin && !isCurrent) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.warningBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'ADMIN',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.people_alt_rounded, size: 13, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          '${fam.memberCount} ${fam.memberCount == 1 ? 'member' : 'members'}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        if (fam.adminName != null && fam.adminName!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text('•', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Admin: ${fam.adminName}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Action Icon
              if (isCurrent)
                const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 22)
              else
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String query) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              query.isEmpty ? 'No family groups found' : 'No matches for "$query"',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              query.isEmpty
                  ? 'Use the button below to join or create a family group.'
                  : 'You can create a new family group with this name.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            if (query.isNotEmpty) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _switchGroup(query),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('Create or Join "$query"'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

