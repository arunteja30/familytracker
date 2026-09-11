import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Zero-Cost Client-Side Notification Service
///
/// Dispatches native heads-up notifications with sound, vibration, and high priority
/// directly on device when peer-to-peer Firebase events arrive (SOS Panic, Low Battery, etc.)
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;

  /// Initialize local notification channels for Android & iOS
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      );

      await _notificationsPlugin.initialize(initSettings);

      // Create Android High-Priority Emergency Channel
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidImpl = _notificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();

        if (androidImpl != null) {
          const emergencyChannel = AndroidNotificationChannel(
            'family_emergency_channel',
            'Family Emergency & SOS Alerts',
            description:
                'Critical high-priority emergency alerts from family members',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          );

          const alertChannel = AndroidNotificationChannel(
            'family_status_channel',
            'Family Safety & Battery Updates',
            description: 'Low battery and safety status notifications',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          );

          await androidImpl.createNotificationChannel(emergencyChannel);
          await androidImpl.createNotificationChannel(alertChannel);
          await androidImpl.requestNotificationsPermission();
        }
      }

      _isInitialized = true;
      debugPrint('[NotificationService] Local notifications initialized successfully.');
    } catch (e) {
      debugPrint('[NotificationService] Initialization error: $e');
    }
  }

  /// Show high-priority Emergency SOS heads-up notification
  static Future<void> showSosAlert({
    required String senderName,
    required String senderPhone,
    required String address,
  }) async {
    try {
      await initialize();

      const androidDetails = AndroidNotificationDetails(
        'family_emergency_channel',
        'Family Emergency & SOS Alerts',
        channelDescription:
            'Critical high-priority emergency alerts from family members',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        playSound: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(''),
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.critical,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      final body = address.isNotEmpty
          ? '📍 Near: $address\nTap to open live location immediately.'
          : 'Tap to view live location immediately.';

      await _notificationsPlugin.show(
        999,
        '🚨 SOS EMERGENCY: $senderName ($senderPhone)',
        body,
        details,
      );
    } catch (e) {
      debugPrint('[NotificationService] Show SOS alert error: $e');
    }
  }

  /// Show Low Battery Warning notification
  static Future<void> showLowBatteryAlert({
    required String memberName,
    required int batteryLevel,
  }) async {
    try {
      await initialize();

      const androidDetails = AndroidNotificationDetails(
        'family_status_channel',
        'Family Safety & Battery Updates',
        channelDescription: 'Low battery and safety status notifications',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      await _notificationsPlugin.show(
        memberName.hashCode,
        '⚡ Low Battery Alert',
        '$memberName\'s phone is at $batteryLevel%. Remind them to charge soon.',
        details,
      );
    } catch (e) {
      debugPrint('[NotificationService] Show Low Battery error: $e');
    }
  }
}
