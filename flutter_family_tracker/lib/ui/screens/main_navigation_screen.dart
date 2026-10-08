import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../providers/family_provider.dart';
import '../../services/preferences_service.dart';
import '../widgets/buzzing_dot.dart';
import '../widgets/security_pin_guard.dart';
import 'family_dashboard_screen.dart';
import 'all_maps_screen.dart';
import 'family_chat_screen.dart';
import 'places_manager_screen.dart';
import 'settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  final int initialIndex;

  const MainNavigationScreen({
    super.key,
    this.initialIndex = 0,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  late int _currentIndex;
  final Set<int> _activatedTabs = {};
  bool _isPinPromptShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = widget.initialIndex;
    _activatedTabs.add(_currentIndex);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPinOnResume();
    }
  }

  Future<void> _checkPinOnResume() async {
    if (_isPinPromptShowing || !mounted) return;
    if (PreferencesService.isSecurityPinEnabled() &&
        PreferencesService.getSecurityPin() != null) {
      _isPinPromptShowing = true;
      await SecurityPinGuard.show(
        context: context,
        mode: PinGuardMode.verify,
        title: 'FamilyTracker Security Guard',
        subtitle: 'Enter 4-digit PIN to unlock',
      );
      _isPinPromptShowing = false;
    }
  }

  void _onTabTapped(int index) {
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
        _activatedTabs.add(index);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final familyProvider = context.watch<FamilyProvider>();
    final familyName = familyProvider.currentFamilyName;
    final members = familyProvider.familyMembers;
    final locations = familyProvider.memberLocations;
    final userPhone = PreferencesService.getUserPhone() ?? '';
    final hasUnreadChat = familyProvider.hasUnreadChat;

    final List<Widget> screens = [
      // Tab 0: Circle Dashboard
      _activatedTabs.contains(0)
          ? FamilyDashboardScreen(
              onNavigateToTab: _onTabTapped,
            )
          : const SizedBox.shrink(),

      // Tab 1: Live Map Tracking
      _activatedTabs.contains(1)
          ? AllMapsScreen(
              familyName: familyName,
              members: members,
              locations: locations,
            )
          : const SizedBox.shrink(),

      // Tab 2: Family Circle Chat
      _activatedTabs.contains(2)
          ? FamilyChatScreen(
              familyName: familyName,
            )
          : const SizedBox.shrink(),

      // Tab 3: Smart Geofencing & Safe Places
      _activatedTabs.contains(3)
          ? PlacesManagerScreen(
              familyName: familyName,
              userPhone: userPhone,
            )
          : const SizedBox.shrink(),

      // Tab 4: Settings & Security
      _activatedTabs.contains(4)
          ? const SettingsScreen()
          : const SizedBox.shrink(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: _onTabTapped,
            backgroundColor: Colors.white,
            elevation: 0,
            indicatorColor: AppColors.primary.withValues(alpha: 0.15),
            height: 64,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              // 0: Circle
              NavigationDestination(
                icon: const Icon(Icons.people_outline_rounded, size: 22, color: AppColors.textSecondary),
                selectedIcon: const Icon(Icons.people_rounded, size: 22, color: AppColors.primary),
                label: 'Circle',
              ),

              // 1: Live Map
              NavigationDestination(
                icon: const Icon(Icons.map_outlined, size: 22, color: AppColors.textSecondary),
                selectedIcon: const Icon(Icons.map_rounded, size: 22, color: AppColors.primary),
                label: 'Map',
              ),

              // 2: Chat
              NavigationDestination(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded, size: 22, color: AppColors.textSecondary),
                    if (hasUnreadChat)
                      const Positioned(
                        right: -3,
                        top: -3,
                        child: BuzzingDot(size: 7, color: Color(0xFFEF4444)),
                      ),
                  ],
                ),
                selectedIcon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.chat_bubble_rounded, size: 22, color: AppColors.primary),
                    if (hasUnreadChat)
                      const Positioned(
                        right: -3,
                        top: -3,
                        child: BuzzingDot(size: 7, color: Color(0xFFEF4444)),
                      ),
                  ],
                ),
                label: 'Chat',
              ),

              // 3: Safe Places
              NavigationDestination(
                icon: const Icon(Icons.shield_outlined, size: 22, color: AppColors.textSecondary),
                selectedIcon: const Icon(Icons.shield_rounded, size: 22, color: AppColors.primary),
                label: 'Places',
              ),

              // 4: Settings
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined, size: 22, color: AppColors.textSecondary),
                selectedIcon: const Icon(Icons.settings_rounded, size: 22, color: AppColors.primary),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
