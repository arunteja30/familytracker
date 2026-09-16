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
import 'package:permission_handler/permission_handler.dart';
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
  bool _dualCamEnabled = true;
  int _failedAttemptsThreshold = 2;
  bool _isLoadingAdmin = false;
  bool _isTestingAlarm = false;
  bool _isTestingEmail = false;
  bool _offlineSmsEnabled = true;
  bool _isTestingSms = false;

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

  bool _isRtdbSynced = false;

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
          _dualCamEnabled = (config['dualCam'] as bool?) ?? true;
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
            _isRtdbSynced = true;
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
          content: Text('✅ Offline SMS emergency contact saved successfully!'),
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
          content: Text('Please enter an emergency phone number for offline SMS.'),
        ),
      );
      return;
    }

    final hasPerm = await PermissionService.requestSmsPermissionExplicitly(context);
    if (!hasPerm) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('SEND_SMS permission is required to send offline location SMS.'),
          ),
        );
      }
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

    // Save user's alert email under their personal user node in RTDB
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
      const SnackBar(content: Text('Testing alert email dispatch using server credentials from RTDB...')),
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
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.success),
                SizedBox(width: 8),
                Text('Email Verified!'),
              ],
            ),
            content: Text('A security test alert was successfully dispatched to $recipient. Please check your inbox / spam folder!'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
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
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final authProvider = Provider.of<AppAuthProvider>(context, listen: false);
      await authProvider.signOut();

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
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.primary,
                      child: const Icon(
                        Icons.person_rounded,
                        size: 32,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            phone.isNotEmpty ? phone : 'Family Member',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Active Group: ${FamilyProvider.formatFamilyDisplayName(familyName)}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Anti-Theft & Intruder Protection Card
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: _isDeviceAdminActive
                      ? AppColors.primary.withValues(alpha: 0.4)
                      : Colors.transparent,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row with Shield and Status Badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (_isDeviceAdminActive ? AppColors.primary : Colors.grey)
                                .withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.security_rounded,
                            color: _isDeviceAdminActive ? AppColors.primary : Colors.grey,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Anti-Theft Protection',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Device Administrator & Intruder Defense',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _isDeviceAdminActive
                                ? AppColors.success.withValues(alpha: 0.15)
                                : AppColors.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _isDeviceAdminActive ? 'Active' : 'Disabled',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _isDeviceAdminActive
                                  ? AppColors.success
                                  : AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Admin Activation Action Tile
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.bgApp,
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
                            color: _isDeviceAdminActive
                                ? AppColors.primary
                                : Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _isDeviceAdminActive
                                  ? 'Device Administrator is granted. Failed unlock detection is active.'
                                  : 'Device Admin required to detect failed lockscreen attempts.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textPrimary,
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              _isLoadingAdmin
                                  ? '...'
                                  : (_isDeviceAdminActive
                                      ? 'Deactivate'
                                      : 'Enable Admin'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Switches for Anti-Theft, Siren, Dual Camera
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Trigger on 2 Wrong Passwords',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                      ),
                      subtitle: const Text(
                        'Automatically triggers siren alarm and secret camera capture when PIN/password is failed 2 times.',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                      value: _antiTheftEnabled,
                      activeThumbColor: AppColors.primary,
                      onChanged: (val) {
                        setState(() => _antiTheftEnabled = val);
                        _saveAntiTheftConfig();
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Sound Loud Siren Alarm',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                      ),
                      subtitle: const Text(
                        'Plays loud siren alarm on device at max volume upon 2 wrong unlock attempts.',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                      value: _sirenEnabled,
                      activeThumbColor: AppColors.primary,
                      onChanged: (val) {
                        setState(() => _sirenEnabled = val);
                        _saveAntiTheftConfig();
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Capture Front & Back Camera',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                      ),
                      subtitle: const Text(
                        'Silently takes photos from front camera (intruder face) and rear camera.',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                      value: _dualCamEnabled,
                      activeThumbColor: AppColors.primary,
                      onChanged: (val) async {
                        if (val) {
                          final granted = await PermissionService.requestCameraPermissionExplicitly(context);
                          if (!granted) return;
                        }
                        setState(() => _dualCamEnabled = val);
                        _saveAntiTheftConfig();
                      },
                    ),
                    const SizedBox(height: 14),

                    // Alert Recipient Email
                    const Text(
                      'Alert Recipient Email',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Secret photos, timestamp, battery level, and GPS location link will be sent to this email instantly.',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'your.alert.email@gmail.com',
                        prefixIcon: const Icon(Icons.email_outlined, size: 18, color: AppColors.primary),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_done_rounded, color: Colors.green, size: 14),
                              SizedBox(width: 6),
                              Text(
                                'Server Dispatch: Auto-configured via RTDB (/EmailConfig)',
                                style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Save and Test Email Buttons Row
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _saveAntiTheftConfig,
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: const Text('Save Alert Email'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isTestingEmail ? null : _testEmailDispatch,
                            icon: _isTestingEmail
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.send_rounded, size: 16),
                            label: Text(_isTestingEmail ? 'Sending...' : 'Test Email'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Test Alarm & Capture Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isTestingAlarm
                                ? null
                                : () async {
                                    final hasCam = await PermissionService.requestCameraPermissionExplicitly(context);
                                    if (!hasCam) return;
                                    final email = _emailController.text.trim();
                                    if (email.isEmpty) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          backgroundColor: AppColors.warning,
                                          content: Text(
                                              'Please enter and save your alert email first.'),
                                        ),
                                      );
                                      return;
                                    }
                                    setState(() => _isTestingAlarm = true);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Triggering test alarm & camera capture... Check your email shortly!'),
                                      ),
                                    );
                                    await NativeService.testIntruderAlarm(
                                      alertEmail: email,
                                      playSiren: _sirenEnabled,
                                      dualCam: _dualCamEnabled,
                                    );
                                    await Future.delayed(
                                        const Duration(seconds: 4));
                                    if (mounted) {
                                      setState(() => _isTestingAlarm = false);
                                    }
                                  },
                            icon: const Icon(Icons.videocam_rounded, size: 16),
                            label: Text(
                              _isTestingAlarm
                                  ? 'Testing...'
                                  : 'Test Alarm & Capture',
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Stop Alarm Siren',
                          onPressed: () => NativeService.stopIntruderAlarm(),
                          icon: const Icon(Icons.volume_off_rounded,
                              color: AppColors.danger, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // View Private Intruder Photo Vault Button
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
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Offline SMS Location Tracking (15-Min Interval) Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sms_failed_rounded, color: AppColors.primary, size: 22),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Offline SMS Location Tracking',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
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
                    const SizedBox(height: 6),
                    const Text(
                      'When your phone has no internet (Wi-Fi/Mobile Data is OFF), the background service automatically dispatches an SMS with your live GPS location & battery status every 15 minutes to your emergency contact.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 14),

                    // Interval badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer_outlined, size: 14, color: AppColors.primary),
                          SizedBox(width: 6),
                          Text(
                            'Dispatch Frequency: Every 15 minutes (Offline Only)',
                            style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Recipient Emergency Phone Number
                    const Text(
                      'Emergency / Family SMS Recipient Phone',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _offlineSmsPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: '+91 98765 43210',
                        prefixIcon: const Icon(Icons.phone_android_rounded, size: 18, color: AppColors.primary),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Save and Test SMS Row
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _saveOfflineSmsConfig,
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: const Text('Save Contact'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isTestingSms ? null : _testOfflineSmsDispatch,
                            icon: _isTestingSms
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.send_to_mobile_rounded, size: 16),
                            label: Text(_isTestingSms ? 'Sending...' : 'Test SMS'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Auto-Start & OEM Battery Settings Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.power_settings_new_rounded, color: AppColors.primary, size: 22),
                        SizedBox(width: 10),
                        Text(
                          'Auto-Start & Background Run',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Ensure FamilyTracker starts automatically when your phone turns on and never gets killed in the background.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 14),
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
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
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
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // App Version & Check for Updates Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.system_update_rounded, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'App Version',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'v${AppConstants.appVersionName} (Build ${AppConstants.appVersionCode})',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Checking for latest updates...')),
                        );
                        final hasUpdate = await AppUpdateService.checkAndPromptUpdate(context);
                        if (!hasUpdate && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: AppColors.success,
                              content: Text('You are on the latest version!'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Check Update'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Sign Out Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout_rounded, color: AppColors.danger),
                label: const Text(
                  'Sign Out',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.danger),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
