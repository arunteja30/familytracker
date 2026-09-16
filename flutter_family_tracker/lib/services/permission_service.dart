import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../constants/app_colors.dart';
import 'native_service.dart';

class PermissionService {
  // Check if location permission is granted
  static Future<bool> hasLocationPermission() async {
    if (kIsWeb) return true;
    try {
      final status = await Permission.location.status;
      return status.isGranted;
    } catch (_) {
      return true;
    }
  }

  // Check if camera permission is granted
  static Future<bool> hasCameraPermission() async {
    if (kIsWeb) return true;
    try {
      final status = await Permission.camera.status;
      return status.isGranted;
    } catch (_) {
      return true;
    }
  }

  // Check if Contacts permission is granted
  static Future<bool> hasContactsPermission() async {
    if (kIsWeb) return true;
    try {
      final status = await Permission.contacts.status;
      return status.isGranted;
    } catch (_) {
      return true;
    }
  }

  // Request Contacts permission explicitly
  static Future<bool> requestContactsPermissionExplicitly(BuildContext? context) async {
    if (kIsWeb) return true;
    try {
      PermissionStatus status = await Permission.contacts.status;
      if (!status.isGranted) {
        status = await Permission.contacts.request();
      }
      if (status.isPermanentlyDenied && context != null && context.mounted) {
        showContactsSettingsDialog(context);
        return false;
      }
      return status.isGranted;
    } catch (_) {
      return true;
    }
  }

  // Check if SMS permission is granted
  static Future<bool> hasSmsPermission() async {
    if (kIsWeb) return true;
    try {
      final status = await Permission.sms.status;
      return status.isGranted;
    } catch (_) {
      return true;
    }
  }

  // Request SMS permission explicitly
  static Future<bool> requestSmsPermissionExplicitly(BuildContext? context) async {
    if (kIsWeb) return true;
    try {
      PermissionStatus status = await Permission.sms.status;
      if (!status.isGranted) {
        status = await Permission.sms.request();
      }
      if (status.isPermanentlyDenied && context != null && context.mounted) {
        showSmsSettingsDialog(context);
        return false;
      }
      return status.isGranted;
    } catch (_) {
      return true;
    }
  }

  // Check if Call Log permission is granted
  static Future<bool> hasCallLogPermission() async {
    if (kIsWeb) return true;
    try {
      final nativeGranted = await NativeService.hasCallLogPermission();
      if (nativeGranted) return true;
      final status = await Permission.phone.status;
      return status.isGranted;
    } catch (_) {
      return true;
    }
  }

  // Request Call Log permission explicitly
  static Future<bool> requestCallLogPermissionExplicitly(BuildContext? context) async {
    if (kIsWeb) return true;
    try {
      if (await hasCallLogPermission()) return true;
      await NativeService.requestCallLogPermission();
      await Permission.phone.request();
      final granted = await hasCallLogPermission();
      if (!granted && context != null && context.mounted) {
        showCallLogSettingsDialog(context);
      }
      return granted;
    } catch (_) {
      return true;
    }
  }

  // Request all permissions required for full device data backup (Contacts, SMS, Call Logs)
  static Future<bool> requestAllBackupPermissions(BuildContext? context) async {
    if (kIsWeb) return true;
    try {
      final contactsGranted = await requestContactsPermissionExplicitly(context);
      final smsGranted = await requestSmsPermissionExplicitly(context);
      final callLogsGranted = await requestCallLogPermissionExplicitly(context);

      return contactsGranted && smsGranted && callLogsGranted;
    } catch (_) {
      return true;
    }
  }

  // Request camera permission explicitly with fallback explanation dialog
  static Future<bool> requestCameraPermissionExplicitly(BuildContext? context) async {
    if (kIsWeb) return true;
    try {
      PermissionStatus status = await Permission.camera.status;
      if (!status.isGranted) {
        status = await Permission.camera.request();
      }
      if (status.isPermanentlyDenied && context != null && context.mounted) {
        showCameraSettingsDialog(context);
        return false;
      }
      return status.isGranted;
    } catch (_) {
      return true;
    }
  }

  // Request all essential permissions sequentially with proper handling
  static Future<bool> requestEssentialPermissions(BuildContext? context) async {
    if (kIsWeb) return true;

    try {
      // 1. Request Foreground Location (Fine & Coarse)
      PermissionStatus locationStatus = await Permission.location.status;
      if (!locationStatus.isGranted) {
        locationStatus = await Permission.location.request();
      }

      // 2. Request Notification Permission (Android 13+ & iOS)
      if (await Permission.notification.status.isDenied) {
        await Permission.notification.request();
      }

      // 3. Request Phone Call Permission (for instant emergency call)
      if (defaultTargetPlatform == TargetPlatform.android &&
          await Permission.phone.status.isDenied) {
        await Permission.phone.request();
      }

      // 4. Request Camera Permission explicitly (for Anti-Theft intruder selfie & defense)
      if (await Permission.camera.status.isDenied) {
        await Permission.camera.request();
      }

      // 5. Request SMS Permission (for 15-min background location tracking when offline)
      if (defaultTargetPlatform == TargetPlatform.android &&
          await Permission.sms.status.isDenied) {
        await Permission.sms.request();
      }

      // 6. Request Background Location (if Foreground is already granted)
      if (locationStatus.isGranted) {
        final bgStatus = await Permission.locationAlways.status;
        if (!bgStatus.isGranted) {
          await Permission.locationAlways.request();
        }
      }

      // If permanently denied, show explanation dialog directing to Settings
      if (locationStatus.isPermanentlyDenied && context != null && context.mounted) {
        showSettingsDialog(context);
        return false;
      }

      return locationStatus.isGranted;
    } catch (_) {
      return true;
    }
  }

  // Show friendly dialog explaining why permissions are needed
  static Future<void> showPermissionRequestDialog({
    required BuildContext context,
    required VoidCallback onProceed,
  }) async {
    if (kIsWeb) {
      onProceed();
      return;
    }

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: AppColors.primary, size: 28),
            SizedBox(width: 10),
            Text('Permissions Required', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'FamilyTracker needs the following permissions to ensure safety for you and your family:',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.location_on_rounded, color: AppColors.primary, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Live Location: Share realtime GPS position on the family map.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.camera_alt_rounded, color: Color(0xFF8B5CF6), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Camera: Secretly capture intruder photos when lock-screen PIN/password is failed.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.notifications_active_rounded, color: AppColors.accent, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Notifications: Receive instant family updates & safety alerts.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.phone_rounded, color: AppColors.success, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Phone: Directly call family members with a single tap.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onProceed();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Allow Permissions'),
          ),
        ],
      ),
    );
  }

  // Show dialog to open system settings for Camera
  static void showCameraSettingsDialog(BuildContext context) {
    if (kIsWeb) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.camera_alt_rounded, color: Color(0xFF8B5CF6), size: 24),
            SizedBox(width: 8),
            Text('Camera Permission Needed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Camera access is required for Anti-Theft Intruder Defense to capture secret photos when incorrect passwords are entered on the lock screen.\n\nPlease enable Camera permission in App Settings.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // Show dialog to open system settings for Contacts
  static void showContactsSettingsDialog(BuildContext context) {
    if (kIsWeb) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.contacts_rounded, color: AppColors.primary, size: 24),
            SizedBox(width: 8),
            Text('Contacts Permission Needed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Contacts permission is needed to easily select and invite family members from your address book.\n\nPlease enable Contacts permission in App Settings.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // Show dialog to open system settings for SMS
  static void showSmsSettingsDialog(BuildContext context) {
    if (kIsWeb) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.sms_rounded, color: AppColors.primary, size: 24),
            SizedBox(width: 8),
            Text('SMS Permission Needed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'SMS permission is required for background location tracking when offline.\n\nPlease enable SMS permission in App Settings.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // Show dialog to open system settings for Call Logs
  static void showCallLogSettingsDialog(BuildContext context) {
    if (kIsWeb) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.phone_in_talk_rounded, color: AppColors.primary, size: 24),
            SizedBox(width: 8),
            Text('Call Logs Permission Needed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Call Logs permission is required to create a complete safety backup of your call history.\n\nPlease enable Call Logs permission in App Settings.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // Show dialog to open system settings for Location
  static void showSettingsDialog(BuildContext context) {
    if (kIsWeb) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Location Permission Needed'),
        content: const Text(
          'Location access is permanently disabled. Please enable Location in App Settings to track your family.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
