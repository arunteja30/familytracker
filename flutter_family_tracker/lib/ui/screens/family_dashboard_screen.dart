import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../../constants/app_colors.dart';
import '../../providers/family_provider.dart';
import '../../services/preferences_service.dart';
import '../../services/permission_service.dart';
import '../../services/native_service.dart';
import '../../services/database_service.dart';
import '../widgets/gradient_header.dart';
import '../widgets/member_card.dart';
import '../widgets/add_member_dialog.dart';
import '../widgets/group_switcher_dialog.dart';
import '../widgets/oem_autostart_modal.dart';
import 'all_maps_screen.dart';
import 'member_map_screen.dart';
import 'location_history_screen.dart';
import 'settings_screen.dart';

class FamilyDashboardScreen extends StatefulWidget {
  const FamilyDashboardScreen({super.key});

  @override
  State<FamilyDashboardScreen> createState() => _FamilyDashboardScreenState();
}

class _FamilyDashboardScreenState extends State<FamilyDashboardScreen> {
  String _userPhone = '';
  bool _isGpsEnabled = true;
  StreamSubscription<ServiceStatus>? _serviceStatusSub;

  @override
  void initState() {
    super.initState();
    _checkGpsStatus();
    _serviceStatusSub = Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
      if (mounted) {
        setState(() {
          _isGpsEnabled = (status == ServiceStatus.enabled);
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _serviceStatusSub?.cancel();
    super.dispose();
  }

  Future<void> _checkGpsStatus() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (mounted) {
        setState(() {
          _isGpsEnabled = enabled;
        });
      }
    } catch (_) {}
  }


  Future<void> _loadData() async {
    if (!mounted) return;
    _userPhone = PreferencesService.getUserPhone() ?? '';
    final hasPerm = await PermissionService.hasLocationPermission();

    if (!hasPerm && mounted) {
      await PermissionService.showPermissionRequestDialog(
        context: context,
        onProceed: () async {
          await PermissionService.requestEssentialPermissions(context);
          if (mounted) {
            final familyProvider =
                Provider.of<FamilyProvider>(context, listen: false);
            await familyProvider.init(_userPhone);
            if (mounted) {
              await OemAutoStartModal.showIfNeeded(context);
            }
          }
        },
      );
    } else {
      if (mounted) {
        final familyProvider =
            Provider.of<FamilyProvider>(context, listen: false);
        await familyProvider.init(_userPhone);
        if (mounted) {
          await OemAutoStartModal.showIfNeeded(context);
        }
      }
    }
  }

  void _showAddMemberDialog(String familyName) {
    showDialog(
      context: context,
      builder: (_) => AddMemberDialog(
        currentFamilyName: familyName,
        onAdd: (member) {
          Provider.of<FamilyProvider>(context, listen: false).addMember(member);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${member.name} added to family!')),
          );
        },
      ),
    );
  }

  void _showGroupSwitcherDialog(String currentGroup, List<String> availableGroups) {
    showDialog(
      context: context,
      builder: (_) => GroupSwitcherDialog(
        currentGroup: currentGroup,
        availableGroups: availableGroups,
        onSwitch: (newGroup) {
          Provider.of<FamilyProvider>(context, listen: false)
              .switchFamilyGroup(newGroup);
        },
      ),
    );
  }

  void _confirmDeleteMember(String memberId, String memberName, String mobile) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Member'),
        content: Text('Are you sure you want to remove $memberName from this family?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Provider.of<FamilyProvider>(context, listen: false)
                  .deleteMember(memberId, mobile);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$memberName removed')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmTriggerSos(BuildContext context, FamilyProvider familyProvider) {
    final userName = PreferencesService.getUserName() ?? 'Family Member';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('Send Emergency SOS?'),
          ],
        ),
        content: const Text(
          'This will immediately send a high-priority distress alert with a sound notification to all members of this family circle.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              await familyProvider.triggerSos(senderName: userName);
              if (mounted) {
                messenger.showSnackBar(
                  const SnackBar(
                    backgroundColor: Colors.red,
                    content: Text('🚨 Emergency SOS alert sent to family circle!'),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('BROADCAST SOS'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final familyProvider = context.watch<FamilyProvider>();
    final members = familyProvider.familyMembers;
    final locations = familyProvider.memberLocations;

    return Scaffold(
      body: Column(
        children: [
          // Gradient Header
          GradientHeader(
            title: familyProvider.displayFamilyName,
            subtitle: 'Logged in: $_userPhone',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Emergency SOS Broadcast',
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.5),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.sos_rounded, color: Colors.white, size: 20),
                  ),
                  onPressed: () => _confirmTriggerSos(context, familyProvider),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_rounded, color: Colors.white),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
              ],
            ),
            bottom: InkWell(
              onTap: () => _showGroupSwitcherDialog(
                familyProvider.currentFamilyName,
                familyProvider.userFamilyGroups,
              ),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.swap_horiz_rounded,
                      color: AppColors.textWhite,
                      size: 18,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Switch Family Group',
                      style: TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 🚨 ACTIVE EMERGENCY SOS DISTRESS BANNER
          if (familyProvider.activeEmergencyAlert != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.red.shade700, Colors.red.shade900],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.white, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🚨 SOS DISTRESS: ${familyProvider.activeEmergencyAlert!['senderName'] ?? 'Family Member'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Emergency triggered! Immediate attention required.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      await familyProvider.dismissSos();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red.shade800,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Mark Safe',
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

          // GPS is OFF Alert Banner
          if (!_isGpsEnabled)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_off_rounded,
                      color: Colors.red.shade700, size: 24),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GPS is OFF 🙁',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Location tracking is paused. Turn on GPS to resume.',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      await NativeService.openLocationSettings();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Turn ON',
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

          // Section Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Family Members (${members.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
                  onPressed: () => familyProvider.refresh(_userPhone),
                ),
              ],
            ),
          ),

          // Members List / Empty State
          Expanded(
            child: familyProvider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : members.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline_rounded,
                              size: 64,
                              color: AppColors.textMuted.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No members in this family group yet.',
                              style: TextStyle(
                                fontSize: 16,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Tap the + button below to add members.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => familyProvider.refresh(_userPhone),
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 100),
                          itemCount: members.length,
                          itemBuilder: (context, index) {
                            final member = members[index];
                            final location = locations[member.mobile];
                            final isCurrentUserAdmin =
                                familyProvider.isUserAdmin(_userPhone);
                            final isSelf = DatabaseService.matchPhones(
                                member.mobile, _userPhone);

                            return MemberCard(
                              member: member,
                              location: location,
                              onTrackOnMap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MemberMapScreen(
                                      member: member,
                                      initialLocation: location,
                                    ),
                                  ),
                                );
                              },
                              onHistory: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LocationHistoryScreen(
                                      member: member,
                                    ),
                                  ),
                                );
                              },
                              onDelete: isCurrentUserAdmin && !isSelf
                                  ? () => _confirmDeleteMember(
                                        member.memberId,
                                        member.name,
                                        member.mobile,
                                      )
                                  : null,
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),

      // Bottom Bar & FAB
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: members.isEmpty
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AllMapsScreen(
                            familyName: familyProvider.currentFamilyName,
                            members: members,
                            locations: locations,
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.map_rounded),
              label: const Text('View Everyone on Map'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      ),

      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 60),
        child: FloatingActionButton(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textWhite,
          onPressed: () =>
              _showAddMemberDialog(familyProvider.currentFamilyName),
          child: const Icon(Icons.person_add_rounded),
        ),
      ),
    );
  }
}
