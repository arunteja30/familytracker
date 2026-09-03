import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../constants/app_colors.dart';

class PermissionService {
  // Check if location permission is granted
  static Future<bool> hasLocationPermission() async {
    final status = await Permission.location.status;
    return status.isGranted;
  }

  // Request all essential permissions sequentially with proper handling
  static Future<bool> requestEssentialPermissions(BuildContext? context) async {
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
    if (Platform.isAndroid && await Permission.phone.status.isDenied) {
      await Permission.phone.request();
    }

    // 4. Request Background Location (if Foreground is already granted)
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
  }

  // Show friendly dialog explaining why permissions are needed
  static Future<void> showPermissionRequestDialog({
    required BuildContext context,
    required VoidCallback onProceed,
  }) async {
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

  // Show dialog to open system settings
  static void showSettingsDialog(BuildContext context) {
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
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
