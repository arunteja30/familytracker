import 'package:flutter/material.dart';

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
  String createdBy;
  int createdAt;

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
    this.createdBy = '',
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  factory GeofencePlaceModel.fromJson(Map<dynamic, dynamic> json, [String? fallbackId]) {
    double parseDouble(dynamic val, double fallback) {
      if (val == null) return fallback;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString()) ?? fallback;
    }

    PlaceCategory parseCategory(dynamic val) {
      final str = val?.toString().toLowerCase() ?? '';
      for (final cat in PlaceCategory.values) {
        if (cat.name == str) return cat;
      }
      return PlaceCategory.custom;
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
      createdBy: json['createdBy']?.toString() ?? '',
      createdAt: json['createdAt'] is num
          ? (json['createdAt'] as num).toInt()
          : (int.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch),
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
      'createdBy': createdBy,
      'createdAt': createdAt,
    };
  }
}
