import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../providers/family_provider.dart';
import '../../services/preferences_service.dart';
import '../widgets/buzzing_dot.dart';
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

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _onTabTapped(int index) {
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
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
      FamilyDashboardScreen(
        onNavigateToTab: _onTabTapped,
      ),

      // Tab 1: Live Map Tracking
      AllMapsScreen(
        familyName: familyName,
        members: members,
        locations: locations,
      ),

      // Tab 2: Family Circle Chat
      FamilyChatScreen(
        familyName: familyName,
      ),

      // Tab 3: Smart Geofencing & Safe Places
      PlacesManagerScreen(
        familyName: familyName,
        userPhone: userPhone,
      ),

      // Tab 4: Settings & Security
      const SettingsScreen(),
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
