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
}

