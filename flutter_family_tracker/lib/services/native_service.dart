import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeService {
  static const MethodChannel _channel =
      MethodChannel('com.mat.familytrack/background_service');

  static bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // Start the native sticky background service (auto-restarting on Android)
  static Future<void> startNativeStickyService() async {
    if (_isMobile) {
      try {
        await _channel.invokeMethod('startNativeStickyService');
      } catch (_) {}
    }
  }

  // Request exemption from Android Doze / Battery Optimization
  static Future<void> requestBatteryOptimizationExemption() async {
    if (_isAndroid) {
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

  // Get detected OEM information (Xiaomi, Oppo, Vivo, Samsung, Apple, etc.)
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

  // Open OEM-specific auto-start or battery management activity
  static Future<bool> openOemAutoStartSettings() async {
    if (_isAndroid) {
      try {
        final bool? result =
            await _channel.invokeMethod<bool>('openOemAutoStartSettings');
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Open OEM / Android Battery Optimization menu to select "No Restrictions" / Unrestricted
  static Future<bool> openBatteryOptimizationSettings() async {
    if (_isAndroid) {
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

  // Update sticky foreground notification with real-time status (e.g. SOS distress or active tracking)
  static Future<void> updateStickyNotification({
    required String title,
    required String text,
    required bool isSosActive,
  }) async {
    if (_isAndroid) {
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

  // Check if Device Administrator is active on Android
  static Future<bool> isDeviceAdminActive() async {
    if (_isAndroid) {
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
    if (_isAndroid) {
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
    if (_isAndroid) {
      try {
        final bool? result =
            await _channel.invokeMethod<bool>('removeDeviceAdmin');
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Fetch Anti-Theft settings from native layer
  static Future<Map<String, dynamic>?> getAntiTheftConfig() async {
    if (_isAndroid) {
      try {
        final result = await _channel.invokeMethod('getAntiTheftConfig');
        if (result is Map) {
          return Map<String, dynamic>.from(result);
        }
      } catch (_) {}
    }
    return null;
  }

  // Save Anti-Theft settings to native layer
  static Future<bool> setAntiTheftConfig({
    String? alertEmail,
    String? senderEmail,
    String? senderPassword,
    bool? enabled,
    bool? siren,
    bool? dualCam,
    int? failedAttempts,
  }) async {
    if (_isAndroid) {
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

  // Test sending alert email and get live response status/error
  static Future<Map<String, dynamic>> testSendAlertEmail({
    required String recipientEmail,
    String? senderEmail,
    String? senderPassword,
  }) async {
    if (_isAndroid) {
      try {
        final result = await _channel.invokeMethod('testSendAlertEmail', {
          'recipientEmail': recipientEmail,
          'senderEmail': senderEmail,
          'senderPassword': senderPassword,
        });
        if (result is Map) {
          return Map<String, dynamic>.from(result);
        }
      } catch (e) {
        return {'success': false, 'error': e.toString()};
      }
    }
    return {'success': false, 'error': 'Not running on Android'};
  }

  // Trigger test siren and test camera capture
  static Future<bool> testIntruderAlarm({
    String? alertEmail,
    bool playSiren = true,
    bool dualCam = true,
  }) async {
    if (_isAndroid) {
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

  // Stop siren alarm if currently ringing
  static Future<void> stopIntruderAlarm() async {
    if (_isAndroid) {
      try {
        await _channel.invokeMethod('stopIntruderAlarm');
      } catch (_) {}
    }
  }

  // Get list of captured intruder photos from private app memory
  static Future<List<Map<String, dynamic>>> getIntruderPhotos() async {
    if (_isAndroid) {
      try {
        final result = await _channel.invokeMethod('getIntruderPhotos');
        if (result is List) {
          return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}
    }
    return [];
  }

  // Explicitly export/save a photo to phone's public gallery upon user confirmation
  static Future<bool> savePhotoToGallery(String filePath) async {
    if (_isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>(
            'savePhotoToGallery', {'filePath': filePath});
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Delete a specific intruder photo from app memory
  static Future<bool> deleteIntruderPhoto(String filePath) async {
    if (_isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>(
            'deleteIntruderPhoto', {'filePath': filePath});
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Clear all intruder photos from app memory
  static Future<bool> clearAllIntruderPhotos() async {
    if (_isAndroid) {
      try {
        final bool? result =
            await _channel.invokeMethod<bool>('clearAllIntruderPhotos');
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Check if Offline SMS location dispatch is enabled
  static Future<bool> isOfflineSmsEnabled() async {
    if (_isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('isOfflineSmsEnabled');
        return result ?? true;
      } catch (_) {}
    }
    return true;
  }

  // Set Offline SMS enabled
  static Future<bool> setOfflineSmsEnabled(bool enabled) async {
    if (_isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>(
            'setOfflineSmsEnabled', {'enabled': enabled});
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Get Offline SMS recipient phone
  static Future<String> getOfflineSmsPhone() async {
    if (_isAndroid) {
      try {
        final String? result = await _channel.invokeMethod<String>('getOfflineSmsPhone');
        return result ?? '';
      } catch (_) {}
    }
    return '';
  }

  // Set Offline SMS recipient phone
  static Future<bool> setOfflineSmsPhone(String phone) async {
    if (_isAndroid) {
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
    if (_isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('hasSmsPermission');
        return result ?? false;
      } catch (_) {}
    }
    return false;
  }

  // Request SEND_SMS permission
  static Future<void> requestSmsPermission() async {
    if (_isAndroid) {
      try {
        await _channel.invokeMethod('requestSmsPermission');
      } catch (_) {}
    }
  }

  // Send a test offline location SMS immediately
  static Future<Map<String, dynamic>> sendTestOfflineSms(String phone) async {
    if (_isAndroid) {
      try {
        final result = await _channel.invokeMethod('sendTestOfflineSms', {'phone': phone});
        if (result is Map) {
          return Map<String, dynamic>.from(result);
        }
      } catch (e) {
        return {'success': false, 'error': e.toString()};
      }
    }
    return {'success': false, 'error': 'Not running on Android'};
  }
}

