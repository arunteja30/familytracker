import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/family_provider.dart';
import '../../services/preferences_service.dart';
import '../../services/native_service.dart';
import '../../services/permission_service.dart';
import '../../services/database_service.dart';
import '../../services/app_update_service.dart';
import '../widgets/oem_autostart_modal.dart';
import '../widgets/intruder_photos_modal.dart';
import 'phone_login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  final _emailController = TextEditingController();
  final _offlineSmsPhoneController = TextEditingController();

  bool _isDeviceAdminActive = false;
  bool _antiTheftEnabled = true;
  bool _sirenEnabled = false;
  bool _dualCamEnabled = false;
  int _failedAttemptsThreshold = 2;
  bool _isLoadingAdmin = false;
  bool _isTestingAlarm = false;
  bool _isTestingEmail = false;
  bool _offlineSmsEnabled = true;
  bool _isTestingSms = false;
  bool _isCheckingUpdate = false;

  // Track expanded state for accordion sections (closed by default)
  final Set<String> _expandedSections = {};

  void _toggleSection(String sectionKey) {
    setState(() {
      if (_expandedSections.contains(sectionKey)) {
        _expandedSections.remove(sectionKey);
      } else {
        _expandedSections.add(sectionKey);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAntiTheftConfig();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAntiTheftConfig();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _emailController.dispose();
    _offlineSmsPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadAntiTheftConfig() async {
    final userPhone = PreferencesService.getUserPhone() ?? '';
    final config = await NativeService.getAntiTheftConfig();
    final isAdmin = await NativeService.isDeviceAdminActive();

    // 1. Fetch user's alertEmail from RTDB profile
    String? rtdbUserAlertEmail;
    if (userPhone.isNotEmpty) {
      rtdbUserAlertEmail = await DatabaseService().getUserAlertEmail(userPhone);
    }

    // 2. Fetch server EmailConfig from Firebase RTDB (/EmailConfig)
    final rtdbServerConfig = await DatabaseService().getEmailConfig();

    // 3. Fetch Offline SMS configuration from native layer
    final smsEnabled = await NativeService.isOfflineSmsEnabled();
    final savedSmsPhone = await NativeService.getOfflineSmsPhone();

    if (mounted) {
      setState(() {
        _isDeviceAdminActive = isAdmin;
        _offlineSmsEnabled = smsEnabled;
        if (savedSmsPhone.isNotEmpty && _offlineSmsPhoneController.text.isEmpty) {
          _offlineSmsPhoneController.text = savedSmsPhone;
        }

        if (config != null) {
          final savedEmail = (config['alertEmail'] ?? '').toString();
          if (savedEmail.isNotEmpty && _emailController.text.isEmpty) {
            _emailController.text = savedEmail;
          }
          _antiTheftEnabled = (config['enabled'] as bool?) ?? true;
          _sirenEnabled = (config['siren'] as bool?) ?? false;
          _dualCamEnabled = (config['dualCam'] as bool?) ?? false;
          _failedAttemptsThreshold = (config['failedAttempts'] as int?) ?? 2;
        }

        // If user profile in RTDB has alertEmail, populate it
        if (rtdbUserAlertEmail != null && rtdbUserAlertEmail.isNotEmpty) {
          _emailController.text = rtdbUserAlertEmail;
          NativeService.setAntiTheftConfig(alertEmail: rtdbUserAlertEmail);
        }

        // If server EmailConfig is available in RTDB, sync it to native layer
        if (rtdbServerConfig != null) {
          final sender = (rtdbServerConfig['senderEmail'] ?? rtdbServerConfig['email'] ?? '').toString();
          final pass = (rtdbServerConfig['appPassword'] ?? rtdbServerConfig['password'] ?? rtdbServerConfig['pass'] ?? '').toString();
          if (pass.isNotEmpty) {
            NativeService.setAntiTheftConfig(
              senderEmail: sender,
              senderPassword: pass,
            );
          }
        }
      });
    }
  }

  Future<void> _saveOfflineSmsConfig() async {
    final phone = _offlineSmsPhoneController.text.trim();
    await NativeService.setOfflineSmsEnabled(_offlineSmsEnabled);
    await NativeService.setOfflineSmsPhone(phone);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.success,
          content: Text('✅ Offline SMS emergency contact saved!'),
        ),
      );
    }
  }

  Future<void> _testOfflineSmsDispatch() async {
    final phone = _offlineSmsPhoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.warning,
          content: Text('Please enter an emergency phone number first.'),
        ),
      );
      return;
    }

    final hasPerm = await PermissionService.requestSmsPermissionExplicitly(context);
    if (!mounted) return;
    if (!hasPerm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('SEND_SMS permission is required to send offline location SMS.'),
        ),
      );
      return;
    }

    setState(() => _isTestingSms = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dispatching test location SMS...')),
    );

    final res = await NativeService.sendTestOfflineSms(phone);
    if (mounted) {
      setState(() => _isTestingSms = false);
      if (res['success'] == true) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.success),
                SizedBox(width: 8),
                Text('SMS Sent!'),
              ],
            ),
            content: Text('A live test location SMS (battery level + Google Maps link) was successfully dispatched to $phone!'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: AppColors.danger),
                SizedBox(width: 8),
                Text('SMS Failed'),
              ],
            ),
            content: Text('Failed to send SMS: ${res['error'] ?? 'Unknown error'}\n\nPlease verify that SIM card has active SMS plan and SEND_SMS permission is granted.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
    }
  }

  Future<void> _saveAntiTheftConfig() async {
    final userPhone = PreferencesService.getUserPhone() ?? '';
    final email = _emailController.text.trim();

    await NativeService.setAntiTheftConfig(
      alertEmail: email,
      enabled: _antiTheftEnabled,
      siren: _sirenEnabled,
      dualCam: _dualCamEnabled,
      failedAttempts: _failedAttemptsThreshold,
    );

    if (userPhone.isNotEmpty && email.isNotEmpty) {
      await DatabaseService().saveUserAlertEmail(userPhone, email);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.success,
          content: Text('Alert email saved and synced to your profile!'),
        ),
      );
    }
  }

  Future<void> _testEmailDispatch() async {
    final recipient = _emailController.text.trim();
    if (recipient.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.warning,
          content: Text('Please enter an Alert Email first.'),
        ),
      );
      return;
    }

    setState(() => _isTestingEmail = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Testing alert email dispatch...')),
    );

    final res = await NativeService.testSendAlertEmail(
      recipientEmail: recipient,
    );

    if (mounted) {
      setState(() => _isTestingEmail = false);
      final success = (res['success'] as bool?) ?? false;
      final error = res['error']?.toString();
      if (success) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.success),
                SizedBox(width: 8),
                Text('Email Verified!'),
              ],
            ),
            content: Text('A security test alert was successfully dispatched to $recipient. Please check your inbox or spam folder!'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: AppColors.danger),
                SizedBox(width: 8),
                Text('Email Dispatch Notice'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(error != null && error.contains('not found in Firebase RTDB')
                    ? '16-digit Google App Password is not yet added in Firebase Realtime Database node "/EmailConfig". Please add "senderEmail" and "appPassword" under /EmailConfig in Firebase Console.'
                    : error != null && error.contains('535')
                        ? 'Google SMTP rejected the credentials (535 Bad Credentials). Please ensure the 16-character App Password under /EmailConfig in Firebase RTDB is valid.'
                        : 'Error: ${error ?? "Unknown dispatch failure."}'),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Dismiss')),
            ],
          ),
        );
      }
    }
  }

  Future<void> _toggleDeviceAdmin() async {
    setState(() => _isLoadingAdmin = true);
    if (_isDeviceAdminActive) {
      await NativeService.removeDeviceAdmin();
    } else {
      await PermissionService.requestCameraPermissionExplicitly(context);
      await NativeService.requestDeviceAdmin();
    }
    await Future.delayed(const Duration(milliseconds: 1000));
    final active = await NativeService.isDeviceAdminActive();
    if (mounted) {
      setState(() {
        _isDeviceAdminActive = active;
        _isLoadingAdmin = false;
      });
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out of FamilyTracker?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted && context.mounted) {
      final authProvider = Provider.of<AppAuthProvider>(context, listen: false);
      await authProvider.signOut();

      if (!context.mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = PreferencesService.getUserPhone() ?? '';
    final familyName = PreferencesService.getUserFamilyName() ?? 'MyFamily';

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(
        title: const Text(
          'Settings & Security',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        elevation: 0,
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. User Profile Header Card
            _buildProfileCard(phone, familyName),
            const SizedBox(height: 16),

            // Section Label
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                'PREFERENCES & MODULES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 6),

            // 2. Anti-Theft & Intruder Protection Section (Expandable)
            _buildExpandableSection(
              sectionKey: 'anti_theft',
              title: 'Anti-Theft & Intruder Defense',
              subtitle: 'Wrong PIN alarm, secret camera capture & vault',
              icon: Icons.security_rounded,
              iconColor: const Color(0xFF6366F1),
              iconBgColor: const Color(0xFFEEF2FF),
              statusBadge: _buildStatusBadge(
                label: _isDeviceAdminActive ? 'Active' : 'Admin Off',
                isActive: _isDeviceAdminActive,
              ),
              child: _buildAntiTheftBody(),
            ),
            const SizedBox(height: 12),

            // 3. Offline SMS Location Tracking Section (Expandable)
            _buildExpandableSection(
              sectionKey: 'offline_sms',
              title: 'Offline SMS Location Tracking',
              subtitle: '15-minute background SMS without internet',
              icon: Icons.sms_rounded,
              iconColor: const Color(0xFF0EA5E9),
              iconBgColor: const Color(0xFFE0F2FE),
              statusBadge: _buildStatusBadge(
                label: _offlineSmsEnabled ? 'Enabled' : 'Disabled',
                isActive: _offlineSmsEnabled,
              ),
              child: _buildOfflineSmsBody(),
            ),
            const SizedBox(height: 12),

            // 4. Background & OEM Battery Section (Expandable)
            _buildExpandableSection(
              sectionKey: 'battery_autostart',
              title: 'Auto-Start & Battery Optimization',
              subtitle: 'Prevent system killing FamilyTracker in background',
              icon: Icons.battery_saver_rounded,
              iconColor: const Color(0xFFF59E0B),
              iconBgColor: const Color(0xFFFEF3C7),
              child: _buildBatteryBody(),
            ),
            const SizedBox(height: 12),

            // 5. App Version & Updates Section (Expandable)
            _buildExpandableSection(
              sectionKey: 'app_update',
              title: 'App Version & System Info',
              subtitle: 'v${AppConstants.appVersionName} (Build ${AppConstants.appVersionCode})',
              icon: Icons.system_update_rounded,
              iconColor: const Color(0xFF10B981),
              iconBgColor: const Color(0xFFD1FAE5),
              child: _buildAppUpdateBody(),
            ),
            const SizedBox(height: 24),

            // 6. Sign Out Button
            _buildSignOutButton(),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // USER PROFILE CARD
  // --------------------------------------------------------------------------
  Widget _buildProfileCard(String phone, String familyName) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_rounded,
              size: 28,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phone.isNotEmpty ? phone : 'Family Member',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        FamilyProvider.formatFamilyDisplayName(familyName),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '• Connected',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // EXPANDABLE SECTION CONTAINER (ACCORDION)
  // --------------------------------------------------------------------------
  Widget _buildExpandableSection({
    required String sectionKey,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    Widget? statusBadge,
    required Widget child,
  }) {
    final isExpanded = _expandedSections.contains(sectionKey);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded ? iconColor.withValues(alpha: 0.3) : AppColors.cardBorder,
          width: isExpanded ? 1.2 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isExpanded ? 0.04 : 0.02),
            blurRadius: isExpanded ? 12 : 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header Tile (Tappable to toggle)
          InkWell(
            onTap: () => _toggleSection(sectionKey),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconBgColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (statusBadge != null) ...[
                    const SizedBox(width: 8),
                    statusBadge,
                  ],
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textMuted,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Collapsible Body
          AnimatedCrossFade(
            firstChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                children: [
                  const Divider(height: 1, color: AppColors.cardBorder),
                  const SizedBox(height: 14),
                  child,
                ],
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
            crossFadeState: isExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // STATUS BADGE WIDGET
  // --------------------------------------------------------------------------
  Widget _buildStatusBadge({required String label, required bool isActive}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isActive ? AppColors.success : AppColors.warning).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isActive ? AppColors.success : AppColors.warning,
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // SECTION 1: ANTI-THEFT & INTRUDER DEFENSE BODY
  // --------------------------------------------------------------------------
  Widget _buildAntiTheftBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Admin Activation Action Tile
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isDeviceAdminActive
                ? AppColors.primary.withValues(alpha: 0.04)
                : Colors.orange.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isDeviceAdminActive
                  ? AppColors.primary.withValues(alpha: 0.2)
                  : Colors.orange.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isDeviceAdminActive
                    ? Icons.admin_panel_settings_rounded
                    : Icons.warning_amber_rounded,
                color: _isDeviceAdminActive ? AppColors.primary : Colors.orange,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isDeviceAdminActive
                      ? 'Device Administrator active. Lockscreen failed attempt detection is enabled.'
                      : 'Device Admin required to detect failed lockscreen unlock attempts.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isLoadingAdmin ? null : _toggleDeviceAdmin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isDeviceAdminActive
                      ? AppColors.danger
                      : AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  elevation: 0,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  _isLoadingAdmin
                      ? '...'
                      : (_isDeviceAdminActive ? 'Deactivate' : 'Enable'),
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Switches
        _buildCompactSwitchTile(
          title: 'Trigger on 2 Wrong Passwords',
          subtitle: 'Captures intruder photo and alerts on 2 failed lockscreen attempts.',
          value: _antiTheftEnabled,
          onChanged: (val) {
            setState(() => _antiTheftEnabled = val);
            _saveAntiTheftConfig();
          },
        ),
        const Divider(height: 1),
        _buildCompactSwitchTile(
          title: 'Sound Loud Siren Alarm',
          subtitle: 'Plays loud siren alarm at maximum volume on 2 wrong unlock attempts.',
          value: _sirenEnabled,
          onChanged: (val) {
            setState(() => _sirenEnabled = val);
            _saveAntiTheftConfig();
          },
        ),
        const Divider(height: 1),
        _buildCompactSwitchTile(
          title: 'Dual Camera Capture (Front & Rear)',
          subtitle: 'Takes high-res intruder face photo and rear environment photo.',
          value: _dualCamEnabled,
          onChanged: (val) async {
            if (val) {
              final granted = await PermissionService.requestCameraPermissionExplicitly(context);
              if (!mounted) return;
              if (!granted) return;
            }
            setState(() => _dualCamEnabled = val);
            _saveAntiTheftConfig();
          },
        ),
        const SizedBox(height: 14),

        // Alert Recipient Email Input
        const Text(
          'Alert Recipient Email',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'Secret photos, timestamp, and GPS location link will be sent to this email.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'your.alert.email@gmail.com',
            hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            prefixIcon: const Icon(Icons.email_outlined, size: 18, color: AppColors.primary),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: AppColors.bgApp,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Save & Test Email Buttons Row
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveAntiTheftConfig,
                icon: const Icon(Icons.check_rounded, size: 15),
                label: const Text('Save Email', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isTestingEmail ? null : _testEmailDispatch,
                icon: _isTestingEmail
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded, size: 15),
                label: Text(_isTestingEmail ? 'Sending...' : 'Test Email', style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Test Alarm and Stop Siren Row
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isTestingAlarm
                    ? null
                    : () async {
                        final hasCam = await PermissionService.requestCameraPermissionExplicitly(context);
                        if (!mounted) return;
                        if (!hasCam) return;
                        final email = _emailController.text.trim();
                        if (email.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: AppColors.warning,
                              content: Text('Please enter and save your alert email first.'),
                            ),
                          );
                          return;
                        }
                        setState(() => _isTestingAlarm = true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Triggering test alarm & capture... Check your inbox!'),
                          ),
                        );
                        await NativeService.testIntruderAlarm(
                          alertEmail: email,
                          playSiren: _sirenEnabled,
                          dualCam: _dualCamEnabled,
                        );
                        await Future.delayed(const Duration(seconds: 4));
                        if (mounted) {
                          setState(() => _isTestingAlarm = false);
                        }
                      },
                icon: const Icon(Icons.videocam_rounded, size: 16),
                label: Text(
                  _isTestingAlarm ? 'Testing...' : 'Test Alarm & Capture',
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.cardBorder),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Stop Alarm Siren',
              onPressed: () => NativeService.stopIntruderAlarm(),
              icon: const Icon(Icons.volume_off_rounded, color: AppColors.danger, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Photo Vault Launcher Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => IntruderPhotosModal.show(context),
            icon: const Icon(Icons.photo_library_rounded, size: 16),
            label: const Text(
              'View Intruder Photo Vault (Private)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.bgSurfaceElevated,
              foregroundColor: AppColors.primary,
              elevation: 0,
              side: const BorderSide(color: AppColors.cardBorder),
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // SECTION 2: OFFLINE SMS TRACKING BODY
  // --------------------------------------------------------------------------
  Widget _buildOfflineSmsBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Switch row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enable Offline SMS Dispatch',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Sends SMS when no internet connectivity is available',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Switch(
              value: _offlineSmsEnabled,
              activeThumbColor: AppColors.primary,
              onChanged: (val) {
                setState(() => _offlineSmsEnabled = val);
                _saveOfflineSmsConfig();
              },
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Info & Interval pill
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0EA5E9).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF0EA5E9).withValues(alpha: 0.2)),
          ),
          child: const Row(
            children: [
              Icon(Icons.timer_outlined, size: 16, color: Color(0xFF0EA5E9)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Frequency: Dispatches every 15 minutes in background while device is offline.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF0369A1), fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Emergency Phone Number field
        const Text(
          'Emergency Contact Phone Number',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _offlineSmsPhoneController,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: '+91 98765 43210',
            hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            prefixIcon: const Icon(Icons.phone_android_rounded, size: 18, color: Color(0xFF0EA5E9)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: AppColors.bgApp,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Save & Test SMS buttons row
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveOfflineSmsConfig,
                icon: const Icon(Icons.check_rounded, size: 15),
                label: const Text('Save Contact', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0EA5E9),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isTestingSms ? null : _testOfflineSmsDispatch,
                icon: _isTestingSms
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_to_mobile_rounded, size: 15),
                label: Text(_isTestingSms ? 'Sending...' : 'Test SMS', style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0EA5E9),
                  side: const BorderSide(color: Color(0xFF0EA5E9)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // SECTION 3: BATTERY & AUTO-START BODY
  // --------------------------------------------------------------------------
  Widget _buildBatteryBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Prevent OEM Background Termination',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        const Text(
          'Manufacturers (Xiaomi, Samsung, Oppo, Vivo, OnePlus) aggressively stop background services unless Auto-Start is granted and Battery is set to "No Restrictions".',
          style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => OemAutoStartModal.show(context, isManualTrigger: true),
                icon: const Icon(Icons.settings_suggest_rounded, size: 16),
                label: const Text('Auto-Start Guide', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => NativeService.openBatteryOptimizationSettings(),
                icon: const Icon(Icons.battery_charging_full_rounded, size: 16),
                label: const Text('Battery Menu', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // SECTION 4: APP UPDATE BODY
  // --------------------------------------------------------------------------
  Widget _buildAppUpdateBody() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FamilyTracker for Android',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              SizedBox(height: 2),
              Text(
                'Version: 1.0.0 (Build 1)',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: _isCheckingUpdate
              ? null
              : () async {
                  setState(() => _isCheckingUpdate = true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Checking for latest updates...')),
                  );
                  final hasUpdate = await AppUpdateService.checkAndPromptUpdate(context);
                  if (mounted) {
                    setState(() => _isCheckingUpdate = false);
                    if (!hasUpdate) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: AppColors.success,
                          content: Text('You are on the latest version!'),
                        ),
                      );
                    }
                  }
                },
          icon: _isCheckingUpdate
              ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.refresh_rounded, size: 15),
          label: const Text('Check Updates', style: TextStyle(fontSize: 11.5)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // SIGN OUT BUTTON
  // --------------------------------------------------------------------------
  Widget _buildSignOutButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _signOut,
        icon: const Icon(Icons.logout_rounded, color: AppColors.danger, size: 18),
        label: const Text(
          'Sign Out',
          style: TextStyle(
            color: AppColors.danger,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.danger, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // HELPER COMPACT SWITCH TILE
  // --------------------------------------------------------------------------
  Widget _buildCompactSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.3),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AppColors.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
