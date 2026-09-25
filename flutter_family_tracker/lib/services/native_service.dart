import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'email_service.dart';

class NativeService {
  static const MethodChannel _channel =
      MethodChannel('com.mat.familytrack/background_service');

  static bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool _handlerInitialized = false;

  /// Listen for native events (e.g. iOS intruder camera capture completions)
  static void initializeIncomingHandlers() {
    if (_handlerInitialized || !_isMobile) return;
    _handlerInitialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onIntruderCaptured') {
        try {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final photoPaths = List<String>.from(args['photoPaths'] ?? []);
          final lat = (args['latitude'] as num?)?.toDouble();
          final lng = (args['longitude'] as num?)?.toDouble();
          final email = args['alertEmail'] as String?;
          if (email != null && email.isNotEmpty) {
            await EmailService.sendIntruderAlertEmail(
              recipientEmail: email,
              photoPaths: photoPaths,
              latitude: lat,
              longitude: lng,
            );
          }
        } catch (e) {
          debugPrint('[NativeService] onIntruderCaptured error: $e');
        }
      }
    });
  }

  // Start the native sticky background service (auto-restarting on Android & background CoreLocation on iOS)
  static Future<void> startNativeStickyService() async {
    initializeIncomingHandlers();
    if (_isMobile) {
      try {
        await _channel.invokeMethod('startNativeStickyService');
      } catch (_) {}
    }
  }

  // Stop the native sticky background service (Android & iOS)
  static Future<void> stopNativeStickyService() async {
    if (_isMobile) {
      try {
        await _channel.invokeMethod('stopNativeStickyService');
      } catch (_) {}
    }
  }

  // Request exemption from Battery Optimization / Background limits
  static Future<void> requestBatteryOptimizationExemption() async {
    if (_isMobile) {
      try {
        await _channel.invokeMethod('requestBatteryOptimizationExemption');
      } catch (_) {}
    }
  }

  // Read device contacts from phonebook (Android & iOS)
  static Future<Map<dynamic, dynamic>?> getDeviceContacts() async {
    if (_isMobile) {
      try {
        final result = await _channel.invokeMethod('getDeviceContacts');
        if (result is Map) {
          return result;
        }
      } catch (_) {}
    }
    return null;
  }

  // Get detected OEM / Device information (Xiaomi, Oppo, Vivo, Samsung, Apple, etc.)
  static Future<Map<String, dynamic>?> getDeviceOemInfo() async {
    if (_isMobile) {
      try {
        final result = await _channel.invokeMethod('getDeviceOemInfo');
        if (result is Map) {
          return Map<String, dynamic>.from(result);
        }
      } catch (_) {}
    }
    return null;
  }

  // Open OEM-specific auto-start or battery management activity (Android) or App Settings (iOS)
  static Future<bool> openOemAutoStartSettings() async {
    if (_isMobile) {
      try {
        final bool? result =
            await _channel.invokeMethod<bool>('openOemAutoStartSettings');
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Open OEM / Android Battery Optimization or iOS Background App Refresh settings
  static Future<bool> openBatteryOptimizationSettings() async {
    if (_isMobile) {
      try {
        final bool? result =
            await _channel.invokeMethod<bool>('openBatteryOptimizationSettings');
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Open OS Location / GPS Settings (Android & iOS)
  static Future<bool> openLocationSettings() async {
    if (_isMobile) {
      try {
        final bool? result =
            await _channel.invokeMethod<bool>('openLocationSettings');
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Update sticky foreground notification with real-time status (Android & iOS)
  static Future<void> updateStickyNotification({
    required String title,
    required String text,
    required bool isSosActive,
  }) async {
    if (_isMobile) {
      try {
        await _channel.invokeMethod('updateStickyNotification', {
          'title': title,
          'text': text,
          'isSosActive': isSosActive,
        });
      } catch (_) {}
    }
  }

  // --- Anti-Theft & Device Admin Methods ---

  // Check if Device Administrator / System Security is active (Android & iOS)
  static Future<bool> isDeviceAdminActive() async {
    if (_isMobile) {
      try {
        final bool? result =
            await _channel.invokeMethod<bool>('isDeviceAdminActive');
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Open System prompt to activate Device Administrator
  static Future<bool> requestDeviceAdmin() async {
    if (_isMobile) {
      try {
        final bool? result =
            await _channel.invokeMethod<bool>('requestDeviceAdmin');
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Remove Device Administrator privilege
  static Future<bool> removeDeviceAdmin() async {
    if (_isMobile) {
      try {
        final bool? result =
            await _channel.invokeMethod<bool>('removeDeviceAdmin');
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Fetch Anti-Theft settings from native layer (Android & iOS)
  static Future<Map<String, dynamic>?> getAntiTheftConfig() async {
    if (_isMobile) {
      try {
        final result = await _channel.invokeMethod('getAntiTheftConfig');
        if (result is Map) {
          return Map<String, dynamic>.from(result);
        }
      } catch (_) {}
    }
    return null;
  }

  // Save Anti-Theft settings to native layer (Android & iOS)
  static Future<bool> setAntiTheftConfig({
    String? alertEmail,
    String? senderEmail,
    String? senderPassword,
    bool? enabled,
    bool? siren,
    bool? dualCam,
    int? failedAttempts,
  }) async {
    if (_isMobile) {
      try {
        final bool? result =
            await _channel.invokeMethod<bool>('setAntiTheftConfig', {
          'alertEmail': alertEmail,
          'senderEmail': senderEmail,
          'senderPassword': senderPassword,
          'enabled': enabled,
          'siren': siren,
          'dualCam': dualCam,
          'failedAttempts': failedAttempts,
        });
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Test sending alert email and get live response status/error (Cross-platform)
  static Future<Map<String, dynamic>> testSendAlertEmail({
    required String recipientEmail,
    String? senderEmail,
    String? senderPassword,
  }) async {
    List<String> samplePaths = [];
    try {
      final photos = await getIntruderPhotos();
      samplePaths = photos
          .map((p) => p['path'] as String?)
          .whereType<String>()
          .take(2)
          .toList();
    } catch (_) {}

    if (_isMobile) {
      try {
        final result = await _channel.invokeMethod('testSendAlertEmail', {
          'recipientEmail': recipientEmail,
          'senderEmail': senderEmail,
          'senderPassword': senderPassword,
        });
        if (result is Map) {
          final resMap = Map<String, dynamic>.from(result);
          if (resMap['fallback'] == true ||
              (resMap['success'] == false &&
                  resMap['error']?.toString().contains('USE_DART_SMTP') == true)) {
            return await EmailService.sendIntruderAlertEmail(
              recipientEmail: recipientEmail,
              senderEmail: senderEmail,
              senderPassword: senderPassword,
              photoPaths: samplePaths,
            );
          }
          return resMap;
        }
      } catch (_) {
        // Fallback to cross-platform EmailService
        return await EmailService.sendIntruderAlertEmail(
          recipientEmail: recipientEmail,
          senderEmail: senderEmail,
          senderPassword: senderPassword,
          photoPaths: samplePaths,
        );
      }
    }
    // Web or desktop fallback
    return await EmailService.sendIntruderAlertEmail(
      recipientEmail: recipientEmail,
      senderEmail: senderEmail,
      senderPassword: senderPassword,
      photoPaths: samplePaths,
    );
  }

  // ============================================================================
  // METHOD: SEND BACKUP FILES TO USER SAVED EMAIL (CROSS-PLATFORM DISPATCH)
  // ============================================================================
  static Future<Map<String, dynamic>> sendBackupFilesEmail({
    required String recipientEmail,
    required List<String> filePaths,
    String? senderEmail,
    String? senderPassword,
  }) async {
    if (_isMobile) {
      try {
        final result = await _channel.invokeMethod('sendBackupFilesEmail', {
          'recipientEmail': recipientEmail,
          'filePaths': filePaths,
        });
        if (result is Map) {
          final resMap = Map<String, dynamic>.from(result);
          if (resMap['fallback'] == true ||
              (resMap['success'] == false &&
                  resMap['error']?.toString().contains('USE_DART_SMTP') == true)) {
            return await EmailService.sendBackupFilesEmail(
              recipientEmail: recipientEmail,
              filePaths: filePaths,
              senderEmail: senderEmail,
              senderPassword: senderPassword,
            );
          }
          return resMap;
        }
      } catch (_) {
        return await EmailService.sendBackupFilesEmail(
          recipientEmail: recipientEmail,
          filePaths: filePaths,
          senderEmail: senderEmail,
          senderPassword: senderPassword,
        );
      }
    }
    return await EmailService.sendBackupFilesEmail(
      recipientEmail: recipientEmail,
      filePaths: filePaths,
      senderEmail: senderEmail,
      senderPassword: senderPassword,
    );
  }

  // Trigger test siren and test camera capture (Android & iOS)
  static Future<bool> testIntruderAlarm({
    String? alertEmail,
    bool playSiren = true,
    bool dualCam = false,
  }) async {
    if (_isMobile) {
      initializeIncomingHandlers();
      try {
        final bool? result =
            await _channel.invokeMethod<bool>('testIntruderAlarm', {
          'alertEmail': alertEmail,
          'playSiren': playSiren,
          'dualCam': dualCam,
        });
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Stop siren alarm if currently ringing (Android & iOS)
  static Future<void> stopIntruderAlarm() async {
    if (_isMobile) {
      try {
        await _channel.invokeMethod('stopIntruderAlarm');
      } catch (_) {}
    }
  }

  // Get list of captured intruder photos from private app memory (Android & iOS)
  static Future<List<Map<String, dynamic>>> getIntruderPhotos() async {
    if (_isMobile) {
      try {
        final result = await _channel.invokeMethod('getIntruderPhotos');
        if (result is List) {
          return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}
    }
    return [];
  }

  // Explicitly export/save a photo to phone's public gallery (Android & iOS)
  static Future<bool> savePhotoToGallery(String filePath) async {
    if (_isMobile) {
      try {
        final bool? result = await _channel.invokeMethod<bool>(
            'savePhotoToGallery', {'filePath': filePath});
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Delete a specific intruder photo from app memory (Android & iOS)
  static Future<bool> deleteIntruderPhoto(String filePath) async {
    if (_isMobile) {
      try {
        final bool? result = await _channel.invokeMethod<bool>(
            'deleteIntruderPhoto', {'filePath': filePath});
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Clear all intruder photos from app memory (Android & iOS)
  static Future<bool> clearAllIntruderPhotos() async {
    if (_isMobile) {
      try {
        final bool? result =
            await _channel.invokeMethod<bool>('clearAllIntruderPhotos');
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Check if Offline SMS location dispatch is enabled (Android & iOS)
  static Future<bool> isOfflineSmsEnabled() async {
    if (_isMobile) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('isOfflineSmsEnabled');
        return result ?? true;
      } catch (_) {}
    }
    return true;
  }

  // Set Offline SMS enabled (Android & iOS)
  static Future<bool> setOfflineSmsEnabled(bool enabled) async {
    if (_isMobile) {
      try {
        final bool? result = await _channel.invokeMethod<bool>(
            'setOfflineSmsEnabled', {'enabled': enabled});
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Get Offline SMS recipient phone (Android & iOS)
  static Future<String> getOfflineSmsPhone() async {
    if (_isMobile) {
      try {
        final String? result = await _channel.invokeMethod<String>('getOfflineSmsPhone');
        return result ?? '';
      } catch (_) {}
    }
    return '';
  }

  // Set Offline SMS recipient phone (Android & iOS)
  static Future<bool> setOfflineSmsPhone(String phone) async {
    if (_isMobile) {
      try {
        final bool? result = await _channel.invokeMethod<bool>(
            'setOfflineSmsPhone', {'phone': phone});
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Check if SEND_SMS permission is granted
  static Future<bool> hasSmsPermission() async {
    if (_isMobile) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('hasSmsPermission');
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Request SEND_SMS permission
  static Future<void> requestSmsPermission() async {
    if (_isMobile) {
      try {
        await _channel.invokeMethod('requestSmsPermission');
      } catch (_) {}
    }
  }

  // Read device call logs (Android only; returns empty on iOS due to sandbox)
  static Future<List<Map<String, dynamic>>> getDeviceCallLogs() async {
    if (_isMobile) {
      try {
        final result = await _channel.invokeMethod('getDeviceCallLogs');
        if (result is List) {
          return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}
    }
    return [];
  }

  // Read device SMS messages (Android only; returns empty on iOS due to sandbox)
  static Future<List<Map<String, dynamic>>> getDeviceSms() async {
    if (_isMobile) {
      try {
        final result = await _channel.invokeMethod('getDeviceSms');
        if (result is List) {
          return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}
    }
    return [];
  }

  // Check if READ_CALL_LOG permission is granted
  static Future<bool> hasCallLogPermission() async {
    if (_isMobile) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('hasCallLogPermission');
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Request READ_CALL_LOG permission
  static Future<void> requestCallLogPermission() async {
    if (_isMobile) {
      try {
        await _channel.invokeMethod('requestCallLogPermission');
      } catch (_) {}
    }
  }

  // Send a test offline location SMS immediately (Android direct or iOS composer)
  static Future<Map<String, dynamic>> sendTestOfflineSms(String phone) async {
    if (_isMobile) {
      try {
        final result = await _channel.invokeMethod('sendTestOfflineSms', {'phone': phone});
        if (result is Map) {
          return Map<String, dynamic>.from(result);
        }
      } catch (e) {
        return {'success': false, 'error': e.toString()};
      }
    }
    return {'success': false, 'error': 'Not running on mobile device'};
  }
}
