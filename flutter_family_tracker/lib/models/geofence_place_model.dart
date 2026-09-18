import 'package:flutter/material.dart';
import '../utils/phone_utils.dart';

enum PlaceCategory {
  home,
  school,
  work,
  gym,
  custom;

  String get displayName {
    switch (this) {
      case PlaceCategory.home:
        return 'Home';
      case PlaceCategory.school:
        return 'School';
      case PlaceCategory.work:
        return 'Work';
      case PlaceCategory.gym:
        return 'Gym';
      case PlaceCategory.custom:
        return 'Safe Zone';
    }
  }

  IconData get icon {
    switch (this) {
      case PlaceCategory.home:
        return Icons.home_rounded;
      case PlaceCategory.school:
        return Icons.school_rounded;
      case PlaceCategory.work:
        return Icons.work_rounded;
      case PlaceCategory.gym:
        return Icons.fitness_center_rounded;
      case PlaceCategory.custom:
        return Icons.place_rounded;
    }
  }

  Color get color {
    switch (this) {
      case PlaceCategory.home:
        return const Color(0xFF10B981); // Emerald Green
      case PlaceCategory.school:
        return const Color(0xFF3B82F6); // Blue
      case PlaceCategory.work:
        return const Color(0xFFF59E0B); // Amber
      case PlaceCategory.gym:
        return const Color(0xFFEC4899); // Pink
      case PlaceCategory.custom:
        return const Color(0xFF6366F1); // Indigo
    }
  }
}

class GeofencePlaceModel {
  String id;
  String familyName;
  String name;
  PlaceCategory category;
  double latitude;
  double longitude;
  double radiusMeters;
  bool notifyOnEntry;
  bool notifyOnExit;
  String targetMemberMobile; // Empty or 'all' = applies to everyone in family; or specific mobile e.g. '+919876543210'
  String targetMemberName;   // e.g. 'Everyone', 'Alex', 'Mom'
  String createdBy;
  int createdAt;

  // Active Schedule / Time Window Controls
  bool isScheduleActive;
  int startHour;
  int startMinute;
  int endHour;
  int endMinute;
  List<int> activeDays; // 1 = Mon, 2 = Tue, ..., 7 = Sun

  GeofencePlaceModel({
    required this.id,
    required this.familyName,
    required this.name,
    this.category = PlaceCategory.custom,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 150.0,
    this.notifyOnEntry = true,
    this.notifyOnExit = true,
    this.targetMemberMobile = '',
    this.targetMemberName = 'Everyone',
    this.createdBy = '',
    int? createdAt,
    this.isScheduleActive = false,
    this.startHour = 8,
    this.startMinute = 0,
    this.endHour = 18,
    this.endMinute = 0,
    List<int>? activeDays,
  })  : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        activeDays = activeDays ?? const [1, 2, 3, 4, 5, 6, 7];

  bool get isForAllMembers => targetMemberMobile.isEmpty || targetMemberMobile == 'all';

  bool appliesToMember(String mobile) {
    if (isForAllMembers) return true;
    if (mobile.isEmpty) return false;
    return PhoneUtils.isSame(targetMemberMobile, mobile);
  }

  /// Evaluates whether the place's active schedule is currently in effect
  bool isCurrentlyActiveInSchedule([DateTime? customTime]) {
    if (!isScheduleActive) return true;
    final now = customTime ?? DateTime.now();

    // Check weekday: 1 = Monday, 7 = Sunday
    if (activeDays.isNotEmpty && !activeDays.contains(now.weekday)) {
      return false;
    }

    final currentMinutes = now.hour * 60 + now.minute;
    final startMinutes = startHour * 60 + startMinute;
    final endMinutes = endHour * 60 + endMinute;

    if (startMinutes <= endMinutes) {
      return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
    } else {
      // Overnight schedule window (e.g. 22:00 to 06:00)
      return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
    }
  }

  /// Human-readable schedule summary (e.g. "Mon-Fri • 08:00 - 15:00")
  String get formattedSchedule {
    if (!isScheduleActive) return 'Active 24/7';
    final sH = startHour.toString().padLeft(2, '0');
    final sM = startMinute.toString().padLeft(2, '0');
    final eH = endHour.toString().padLeft(2, '0');
    final eM = endMinute.toString().padLeft(2, '0');
    final daysStr = activeDays.length == 7
        ? 'Daily'
        : (activeDays.length == 5 && !activeDays.contains(6) && !activeDays.contains(7))
            ? 'Mon-Fri'
            : (activeDays.length == 2 && activeDays.contains(6) && activeDays.contains(7))
                ? 'Weekends'
                : '${activeDays.length} days/wk';
    return '$daysStr • $sH:$sM - $eH:$eM';
  }

  factory GeofencePlaceModel.fromJson(Map<dynamic, dynamic> json, [String? fallbackId]) {
    double parseDouble(dynamic val, double fallback) {
      if (val == null) return fallback;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString()) ?? fallback;
    }

    int parseInt(dynamic val, int fallback) {
      if (val == null) return fallback;
      if (val is num) return val.toInt();
      return int.tryParse(val.toString()) ?? fallback;
    }

    PlaceCategory parseCategory(dynamic val) {
      final str = val?.toString().toLowerCase() ?? '';
      for (final cat in PlaceCategory.values) {
        if (cat.name == str) return cat;
      }
      return PlaceCategory.custom;
    }

    List<int> parseDays(dynamic val) {
      if (val is List) {
        return val.map((e) => int.tryParse(e.toString()) ?? 1).toList();
      }
      return [1, 2, 3, 4, 5, 6, 7];
    }

    return GeofencePlaceModel(
      id: json['id']?.toString() ?? fallbackId ?? '',
      familyName: json['familyName']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Safe Zone',
      category: parseCategory(json['category']),
      latitude: parseDouble(json['latitude'], 0.0),
      longitude: parseDouble(json['longitude'], 0.0),
      radiusMeters: parseDouble(json['radiusMeters'] ?? json['radius'], 150.0),
      notifyOnEntry: json['notifyOnEntry'] != false,
      notifyOnExit: json['notifyOnExit'] != false,
      targetMemberMobile: json['targetMemberMobile']?.toString() ?? '',
      targetMemberName: json['targetMemberName']?.toString() ??
          (json['targetMemberMobile']?.toString().isNotEmpty == true ? 'Individual Member' : 'Everyone'),
      createdBy: json['createdBy']?.toString() ?? '',
      createdAt: json['createdAt'] is num
          ? (json['createdAt'] as num).toInt()
          : (int.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch),
      isScheduleActive: json['isScheduleActive'] == true,
      startHour: parseInt(json['startHour'], 8),
      startMinute: parseInt(json['startMinute'], 0),
      endHour: parseInt(json['endHour'], 18),
      endMinute: parseInt(json['endMinute'], 0),
      activeDays: parseDays(json['activeDays']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'familyName': familyName,
      'name': name,
      'category': category.name,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
      'notifyOnEntry': notifyOnEntry,
      'notifyOnExit': notifyOnExit,
      'targetMemberMobile': targetMemberMobile,
      'targetMemberName': targetMemberName,
      'createdBy': createdBy,
      'createdAt': createdAt,
      'isScheduleActive': isScheduleActive,
      'startHour': startHour,
      'startMinute': startMinute,
      'endHour': endHour,
      'endMinute': endMinute,
      'activeDays': activeDays,
    };
  }
}
