import 'package:flutter/material.dart';

enum AlertType {
  sos,
  intruder,
  placeArrival,
  placeDeparture,
  batteryLow,
  checkIn,
  general;

  static AlertType fromString(String? val) {
    final s = val?.toLowerCase().trim() ?? '';
    if (s.contains('sos') || s.contains('emergency')) return AlertType.sos;
    if (s.contains('intruder') || s.contains('selfie')) return AlertType.intruder;
    if (s.contains('checkin') || s.contains('check_in') || s.contains('safe')) return AlertType.checkIn;
    if (s.contains('arrival') || s.contains('entered') || s.contains('place_arrival')) return AlertType.placeArrival;
    if (s.contains('departure') || s.contains('left') || s.contains('place_departure')) return AlertType.placeDeparture;
    if (s.contains('battery')) return AlertType.batteryLow;
    return AlertType.general;
  }

  String get displayName {
    switch (this) {
      case AlertType.sos:
        return 'SOS Emergency';
      case AlertType.intruder:
        return 'Intruder Alert';
      case AlertType.checkIn:
        return "I'm Safe Check-In";
      case AlertType.placeArrival:
        return 'Place Arrival';
      case AlertType.placeDeparture:
        return 'Place Departure';
      case AlertType.batteryLow:
        return 'Low Battery';
      case AlertType.general:
        return 'Safety Alert';
    }
  }

  IconData get icon {
    switch (this) {
      case AlertType.sos:
        return Icons.emergency_rounded;
      case AlertType.intruder:
        return Icons.security_rounded;
      case AlertType.checkIn:
        return Icons.verified_user_rounded;
      case AlertType.placeArrival:
        return Icons.login_rounded;
      case AlertType.placeDeparture:
        return Icons.logout_rounded;
      case AlertType.batteryLow:
        return Icons.battery_alert_rounded;
      case AlertType.general:
        return Icons.notifications_active_rounded;
    }
  }

  Color get color {
    switch (this) {
      case AlertType.sos:
        return const Color(0xFFDC2626); // Crimson Red
      case AlertType.intruder:
        return const Color(0xFF7C3AED); // Deep Purple
      case AlertType.checkIn:
        return const Color(0xFF059669); // Emerald Green
      case AlertType.placeArrival:
        return const Color(0xFF10B981); // Teal/Emerald Green
      case AlertType.placeDeparture:
        return const Color(0xFF3B82F6); // Blue
      case AlertType.batteryLow:
        return const Color(0xFFF59E0B); // Amber
      case AlertType.general:
        return const Color(0xFF6366F1); // Indigo
    }
  }
}

class AlertItemModel {
  final String id;
  final String familyName;
  final AlertType type;
  final String title;
  final String body;
  final String memberName;
  final String memberMobile;
  final int timestamp;
  final double? latitude;
  final double? longitude;
  final String? placeName;
  final String? extraInfo;

  static const int ttlMilliseconds = 24 * 60 * 60 * 1000; // 24 Hours self-delete TTL

  AlertItemModel({
    required this.id,
    required this.familyName,
    required this.type,
    required this.title,
    required this.body,
    this.memberName = '',
    this.memberMobile = '',
    int? timestamp,
    this.latitude,
    this.longitude,
    this.placeName,
    this.extraInfo,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  /// Check if the alert is older than 24 hours (auto-expire)
  bool get isExpired {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - timestamp) > ttlMilliseconds;
  }

  /// Calculates remaining time before 24-hour auto-delete
  String get remainingTimeText {
    final now = DateTime.now().millisecondsSinceEpoch;
    final remainingMs = ttlMilliseconds - (now - timestamp);
    if (remainingMs <= 0) return 'Expiring soon';

    final totalMinutes = remainingMs ~/ (60 * 1000);
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;

    if (hours > 0) {
      return 'Expires in ${hours}h ${mins}m';
    } else {
      return 'Expires in ${mins}m';
    }
  }

  factory AlertItemModel.fromJson(Map<dynamic, dynamic> json, [String? fallbackId]) {
    double? parseDouble(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString());
    }

    return AlertItemModel(
      id: json['id']?.toString() ?? fallbackId ?? '',
      familyName: json['familyName']?.toString() ?? '',
      type: AlertType.fromString(json['type']?.toString()),
      title: json['title']?.toString() ?? 'Safety Alert',
      body: json['body']?.toString() ?? '',
      memberName: json['memberName']?.toString() ?? '',
      memberMobile: json['memberMobile']?.toString() ?? '',
      timestamp: json['timestamp'] is num
          ? (json['timestamp'] as num).toInt()
          : (int.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch),
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      placeName: json['placeName']?.toString(),
      extraInfo: json['extraInfo']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'familyName': familyName,
      'type': type.name,
      'title': title,
      'body': body,
      'memberName': memberName,
      'memberMobile': memberMobile,
      'timestamp': timestamp,
      'expiresAt': timestamp + ttlMilliseconds,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (placeName != null) 'placeName': placeName,
      if (extraInfo != null) 'extraInfo': extraInfo,
    };
  }
}
