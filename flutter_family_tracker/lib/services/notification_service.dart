import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/alert_item_model.dart';
import 'database_service.dart';

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
    if (kIsWeb || _isInitialized) return;

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

          const chatChannel = AndroidNotificationChannel(
            'family_chat_channel',
            'Family Circle Messages',
            description: 'Group chat notifications from family circle members',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          );

          const geofenceChannel = AndroidNotificationChannel(
            'family_geofence_channel',
            'Safe Place & Geofence Alerts',
            description: 'Arrival and departure notifications for family safe places',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          );

          await androidImpl.createNotificationChannel(emergencyChannel);
          await androidImpl.createNotificationChannel(alertChannel);
          await androidImpl.createNotificationChannel(chatChannel);
          await androidImpl.createNotificationChannel(geofenceChannel);
          await androidImpl.requestNotificationsPermission();
        }
      }

      _isInitialized = true;
      debugPrint('[NotificationService] Local notifications initialized successfully.');
    } catch (e) {
      debugPrint('[NotificationService] Initialization error: $e');
    }
  }

  /// Show high-priority Emergency SOS heads-up notification with rich distress text
  static Future<void> showSosAlert({
    required String senderName,
    required String senderPhone,
    required String address,
    String? familyName,
  }) async {
    try {
      await initialize();

      final locText = address.isNotEmpty ? address : 'Live GPS coordinates available';
      final famText = familyName != null && familyName.isNotEmpty ? ' in $familyName' : '';
      final body = '🚨 SOS DISTRESS ALERT$famText!\n👤 $senderName ($senderPhone) needs urgent help.\n📍 Location: $locText\n\nTap to open live map tracking immediately.';

      final bigTextStyle = BigTextStyleInformation(
        body,
        contentTitle: '🚨 SOS EMERGENCY: $senderName',
        summaryText: '🚨 SOS Emergency Alert',
        htmlFormatBigText: false,
        htmlFormatContentTitle: false,
      );

      final androidDetails = AndroidNotificationDetails(
        'family_emergency_channel',
        'Family Emergency & SOS Alerts',
        channelDescription:
            'Critical high-priority emergency alerts from family members',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
        styleInformation: bigTextStyle,
        category: AndroidNotificationCategory.alarm,
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.critical,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      if (!kIsWeb) {
        await _notificationsPlugin.show(
          999,
          '🚨 SOS EMERGENCY: $senderName ($senderPhone)',
          body,
          details,
        );
        debugPrint('[NotificationService] 🚨 Heads-up SOS notification displayed for $senderName');
      }

      // Log to centralized 24h safety alerts feed
      if (familyName != null && familyName.isNotEmpty) {
        DatabaseService().logAlert(
          AlertItemModel(
            id: '',
            familyName: familyName,
            type: AlertType.sos,
            title: '🚨 SOS EMERGENCY: $senderName',
            body: '$senderName ($senderPhone) triggered distress SOS. Location: $locText',
            memberName: senderName,
            memberMobile: senderPhone,
            extraInfo: address,
          ),
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] Show SOS alert error: $e');
    }
  }

  /// Show active SOS broadcast status notification for the sender
  static Future<void> showSosBroadcastActiveNotification({
    required String familyName,
    required String address,
  }) async {
    try {
      await initialize();

      final locText = address.isNotEmpty ? address : 'Acquiring GPS location';
      final body = '🚨 Emergency distress alert broadcasted to $familyName.\n📍 Location: $locText\nFamily members are being notified.';

      final bigTextStyle = BigTextStyleInformation(
        body,
        contentTitle: '🚨 SOS BROADCAST ACTIVE',
        summaryText: 'SOS Distress Active',
      );

      final androidDetails = AndroidNotificationDetails(
        'family_emergency_channel',
        'Family Emergency & SOS Alerts',
        channelDescription:
            'Critical high-priority emergency alerts from family members',
        importance: Importance.max,
        priority: Priority.max,
        ongoing: true,
        autoCancel: false,
        playSound: true,
        enableVibration: true,
        styleInformation: bigTextStyle,
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      if (!kIsWeb) {
        await _notificationsPlugin.show(
          998,
          '🚨 SOS BROADCAST ACTIVE ($familyName)',
          body,
          details,
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] Show SOS broadcast error: $e');
    }
  }

  /// Cancel any active SOS alerts and broadcast status notifications
  static Future<void> cancelSosAlert() async {
    try {
      if (!kIsWeb) {
        await _notificationsPlugin.cancel(999);
        await _notificationsPlugin.cancel(998);
        debugPrint('[NotificationService] Cancelled SOS notifications (999, 998)');
      }
    } catch (e) {
      debugPrint('[NotificationService] Cancel SOS alert error: $e');
    }
  }

  /// Show Low Battery Warning notification
  static Future<void> showLowBatteryAlert({
    required String memberName,
    required int batteryLevel,
    String? familyName,
    String? memberMobile,
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
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      if (!kIsWeb) {
        await _notificationsPlugin.show(
          memberName.hashCode,
          '⚡ Low Battery Alert',
          '$memberName\'s phone is at $batteryLevel%. Remind them to charge soon.',
          details,
        );
      }

      if (familyName != null && familyName.isNotEmpty) {
        DatabaseService().logAlert(
          AlertItemModel(
            id: '',
            familyName: familyName,
            type: AlertType.batteryLow,
            title: '⚡ Low Battery: $memberName ($batteryLevel%)',
            body: '$memberName\'s phone battery has dropped to $batteryLevel%. Remind them to charge soon.',
            memberName: memberName,
            memberMobile: memberMobile ?? '',
            extraInfo: '$batteryLevel%',
          ),
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] Show Low Battery error: $e');
    }
  }

  /// Show Group or Direct Chat Message notification
  static Future<void> showChatMessageNotification({
    required String senderName,
    required String text,
    required String familyName,
    int? notificationId,
  }) async {
    try {
      await initialize();

      final id = notificationId ?? (DateTime.now().millisecondsSinceEpoch.remainder(100000));
      final title = '💬 $senderName ($familyName)';

      final androidDetails = AndroidNotificationDetails(
        'family_chat_channel',
        'Family Circle Messages',
        channelDescription: 'Group and direct chat notifications from family circle members',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(
          text,
          contentTitle: title,
          summaryText: familyName,
        ),
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      if (!kIsWeb) {
        await _notificationsPlugin.show(
          id,
          title,
          text,
          details,
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] Show Chat Notification error: $e');
    }
  }

  /// Show Data Backup Completion notification
  static Future<void> showBackupCompleteNotification({
    required int contactsCount,
    required int callLogsCount,
    required int smsCount,
    required String formattedSize,
  }) async {
    try {
      await initialize();

      const channel = AndroidNotificationChannel(
        'family_backup_channel',
        'Device Data Backup',
        description: 'Notifications for completed device data backups',
        importance: Importance.high,
        playSound: true,
      );

      final androidImpl = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.createNotificationChannel(channel);
      }

      final body = 'Successfully created separate backup files:\n👤 $contactsCount Contacts • 📞 $callLogsCount Call Logs • 💬 $smsCount SMS ($formattedSize)';

      final androidDetails = AndroidNotificationDetails(
        'family_backup_channel',
        'Device Data Backup',
        channelDescription: 'Notifications for completed device data backups',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: '✅ Device Data Backup Complete',
          summaryText: 'Data Backup',
        ),
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      if (!kIsWeb) {
        await _notificationsPlugin.show(
          997,
          '✅ Device Data Backup Complete',
          body,
          details,
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] Show Backup Complete error: $e');
    }
  }

  /// Show Safe Place Arrival or Departure notification
  static Future<void> showPlaceAlert({
    required String memberName,
    required String placeName,
    required bool isArrival,
    String? familyName,
  }) async {
    try {
      await initialize();

      final emoji = isArrival ? '🏠' : '🚗';
      final action = isArrival ? 'arrived at' : 'left';
      final title = '$emoji $memberName $action $placeName';
      final famText = (familyName != null && familyName.isNotEmpty) ? ' • $familyName' : '';
      final body = '$memberName has safely $action $placeName$famText.';

      final androidDetails = AndroidNotificationDetails(
        'family_geofence_channel',
        'Safe Place & Geofence Alerts',
        channelDescription: 'Arrival and departure notifications for family safe places',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: 'Safe Place Alert',
        ),
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      final notifId = (memberName.hashCode ^ placeName.hashCode ^ (isArrival ? 1 : 2)).abs() % 100000;

      if (!kIsWeb) {
        await _notificationsPlugin.show(
          notifId,
          title,
          body,
          details,
        );
        debugPrint('[NotificationService] 📍 Dispatched place alert: $title');
      }

      if (familyName != null && familyName.isNotEmpty) {
        DatabaseService().logAlert(
          AlertItemModel(
            id: '',
            familyName: familyName,
            type: isArrival ? AlertType.placeArrival : AlertType.placeDeparture,
            title: title,
            body: body,
            memberName: memberName,
            placeName: placeName,
          ),
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] Error showing place alert: $e');
    }
  }

  /// Show Intruder Selfie / Unauthorized Access Alert
  static Future<void> showIntruderAlert({
    required String memberName,
    required String detailsText,
    String? familyName,
    String? photoUrl,
  }) async {
    try {
      await initialize();
      final title = '📸 Intruder Alert: $memberName';
      final body = detailsText.isNotEmpty ? detailsText : 'Wrong lockscreen PIN attempt detected. Intruder selfie captured.';

      const androidDetails = AndroidNotificationDetails(
        'family_status_channel',
        'Family Safety & Battery Updates',
        channelDescription: 'Intruder and safety status notifications',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      if (!kIsWeb) {
        await _notificationsPlugin.show(
          888,
          title,
          body,
          details,
        );
      }

      if (familyName != null && familyName.isNotEmpty) {
        DatabaseService().logAlert(
          AlertItemModel(
            id: '',
            familyName: familyName,
            type: AlertType.intruder,
            title: title,
            body: body,
            memberName: memberName,
            extraInfo: photoUrl,
          ),
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] Show Intruder Alert error: $e');
    }
  }
}

