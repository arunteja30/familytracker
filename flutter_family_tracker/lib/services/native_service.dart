import 'dart:io';
import 'package:flutter/services.dart';

class NativeService {
  static const MethodChannel _channel =
      MethodChannel('com.mat.familytrack/background_service');

  // Start the native sticky background service (auto-restarting)
  static Future<void> startNativeStickyService() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('startNativeStickyService');
      } catch (_) {}
    }
  }

  // Request exemption from Android Doze / Battery Optimization
  static Future<void> requestBatteryOptimizationExemption() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('requestBatteryOptimizationExemption');
      } catch (_) {}
    }
  }
}
