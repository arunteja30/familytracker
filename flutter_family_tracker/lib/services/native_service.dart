import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeService {
  static const MethodChannel _channel =
      MethodChannel('com.mat.familytrack/background_service');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // Start the native sticky background service (auto-restarting)
  static Future<void> startNativeStickyService() async {
    if (_isAndroid) {
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

  // Read device contacts from phonebook
  static Future<Map<dynamic, dynamic>?> getDeviceContacts() async {
    if (_isAndroid) {
      try {
        final result = await _channel.invokeMethod('getDeviceContacts');
        if (result is Map) {
          return result;
        }
      } catch (_) {}
    }
    return null;
  }
}
