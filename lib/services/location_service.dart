import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:intl/intl.dart';
import '../models/location_details_model.dart';
import 'database_service.dart';
import 'geocoding_service.dart';

class LocationService {
  final Battery _battery = Battery();
  final DatabaseService _dbService = DatabaseService();
  StreamSubscription<Position>? _positionStreamSubscription;

  // Check and Request Location Permissions
  Future<bool> checkPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  // Get Current Location & Battery Info Once
  Future<LocationDetailsModel?> getCurrentLocationDetails() async {
    try {
      final hasPermission = await checkPermission();
      if (!hasPermission) return null;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      final batteryLevel = await _battery.batteryLevel;
      final address = await GeocodingService.getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );

      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);

      return LocationDetailsModel(
        latitude: position.latitude,
        longitude: position.longitude,
        timeStamp: now.millisecondsSinceEpoch,
        date: dateStr,
        batteryPercentage: batteryLevel,
        address: address,
        gpsStatus: 'Active',
      );
    } catch (e) {
      return null;
    }
  }

  // Update & Push Single Location
  Future<void> updateAndPushLocation(String mobile) async {
    final location = await getCurrentLocationDetails();
    if (location != null && mobile.isNotEmpty) {
      await _dbService.saveLocation(mobile, location);
    }
  }

  // Start Continuous Background Location Tracking with Foreground Notification
  void startContinuousBackgroundLocationTracking(String mobile) {
    if (mobile.isEmpty) return;

    _positionStreamSubscription?.cancel();

    late LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 30),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 10,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) async {
      try {
        final batteryLevel = await _battery.batteryLevel;
        final address = await GeocodingService.getAddressFromCoordinates(
          position.latitude,
          position.longitude,
        );
        final now = DateTime.now();
        final dateStr = DateFormat('yyyy-MM-dd').format(now);

        final location = LocationDetailsModel(
          latitude: position.latitude,
          longitude: position.longitude,
          timeStamp: now.millisecondsSinceEpoch,
          date: dateStr,
          batteryPercentage: batteryLevel,
          address: address,
          gpsStatus: 'Active',
        );

        await _dbService.saveLocation(mobile, location);
        debugPrint(
            '[FamilyTracker] Background location pushed: (${position.latitude}, ${position.longitude}) - $address');
      } catch (e) {
        debugPrint('[FamilyTracker] Background tracking error: $e');
      }
    });

    debugPrint('[FamilyTracker] Continuous background tracking started for: $mobile');
  }

  // Stop Continuous Tracking
  void stopContinuousTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
  }
}
