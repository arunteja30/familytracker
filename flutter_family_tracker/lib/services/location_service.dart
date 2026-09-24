import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:intl/intl.dart';
import '../models/location_details_model.dart';
import 'database_service.dart';
import 'geocoding_service.dart';
import 'ip_location_service.dart';

class LocationService {
  final Battery _battery = Battery();
  final DatabaseService _dbService = DatabaseService();
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;

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

  // Get Current Location & Battery Info (With IP Fallback when GPS is OFF)
  Future<LocationDetailsModel?> getCurrentLocationDetails() async {
    int batteryLevel = 100;
    try {
      batteryLevel = await _battery.batteryLevel;
    } catch (_) {}

    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);

    // 1. Try Hardware GPS (Fast lastKnown + fresh position)
    try {
      final hasPermission = await checkPermission();
      if (hasPermission) {
        Position? position;

        // Try fast cached location first on mobile (0ms response)
        if (!kIsWeb) {
          try {
            final lastKnown = await Geolocator.getLastKnownPosition();
            if (lastKnown != null && (lastKnown.latitude != 0.0 || lastKnown.longitude != 0.0)) {
              position = lastKnown;
            }
          } catch (_) {}
        }

        // Try fresh location (avoid timeLimit on web to prevent geolocator_web Bad state: Future already completed)
        try {
          final fresh = kIsWeb
              ? await Geolocator.getCurrentPosition(
                  desiredAccuracy: LocationAccuracy.medium,
                )
              : await Geolocator.getCurrentPosition(
                  desiredAccuracy: LocationAccuracy.medium,
                  timeLimit: const Duration(seconds: 5),
                );
          if (fresh.latitude != 0.0 || fresh.longitude != 0.0) {
            position = fresh;
          }
        } catch (_) {}

        if (position != null && (position.latitude != 0.0 || position.longitude != 0.0)) {
          String address = '';
          try {
            address = await GeocodingService.getAddressFromCoordinates(
              position.latitude,
              position.longitude,
            );
          } catch (_) {}

          if (address.isEmpty || address.startsWith('Lat:')) {
            address = 'Lat: ${position.latitude.toStringAsFixed(4)}, Lng: ${position.longitude.toStringAsFixed(4)}';
          }

          final speedKmh = position.speed > 0 ? (position.speed * 3.6) : 0.0;
          final heading = position.heading;

          return LocationDetailsModel(
            latitude: position.latitude,
            longitude: position.longitude,
            timeStamp: now.millisecondsSinceEpoch,
            date: dateStr,
            batteryPercentage: batteryLevel,
            address: address,
            gpsStatus: 'Active',
            speedKmh: speedKmh,
            heading: heading,
          );
        }
      }
    } catch (e) {
      debugPrint('[FamilyTracker] GPS fix failed: $e. Using IP Geolocation fallback.');
    }

    // 2. Fallback: Coarse IP Geolocation when GPS is OFF
    try {
      final ipLocation = await IpLocationService.getCoarseIpLocation();
      if (ipLocation != null) {
        return LocationDetailsModel(
          latitude: ipLocation['lat'] as double,
          longitude: ipLocation['lon'] as double,
          timeStamp: now.millisecondsSinceEpoch,
          date: dateStr,
          batteryPercentage: batteryLevel,
          address: ipLocation['address'] as String,
          gpsStatus: 'IP (Approx)',
        );
      }
    } catch (e) {
      debugPrint('[FamilyTracker] IP location fallback failed: $e');
    }

    return null;
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

    // 1. Immediately fetch & push location on launch so Firebase is updated without waiting for movement
    updateAndPushLocation(mobile);

    _positionStreamSubscription?.cancel();

    late LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 40,
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 30),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.other,
        distanceFilter: 40,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 40,
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

        final speedKmh = position.speed > 0 ? (position.speed * 3.6) : 0.0;
        final heading = position.heading;

        final location = LocationDetailsModel(
          latitude: position.latitude,
          longitude: position.longitude,
          timeStamp: now.millisecondsSinceEpoch,
          date: dateStr,
          batteryPercentage: batteryLevel,
          address: address,
          gpsStatus: 'Active',
          speedKmh: speedKmh,
          heading: heading,
        );

        await _dbService.saveLocation(mobile, location);
        debugPrint(
            '[FamilyTracker] Background location pushed: (${position.latitude}, ${position.longitude}) speed: ${speedKmh.toStringAsFixed(1)}km/h - $address');
      } catch (e) {
        debugPrint('[FamilyTracker] Background tracking error: $e');
      }
    });

    if (!kIsWeb) {
      _serviceStatusSubscription?.cancel();
      _serviceStatusSubscription =
          Geolocator.getServiceStatusStream().listen((status) async {
        if (status == ServiceStatus.disabled) {
          debugPrint(
              '[FamilyTracker] GPS disabled event detected, fetching IP location fallback...');
          try {
            final ipLocation = await IpLocationService.getCoarseIpLocation();
            if (ipLocation != null) {
              final batteryLevel = await _battery.batteryLevel;
              final now = DateTime.now();
              final dateStr = DateFormat('yyyy-MM-dd').format(now);

              final location = LocationDetailsModel(
                latitude: ipLocation['lat'] as double,
                longitude: ipLocation['lon'] as double,
                timeStamp: now.millisecondsSinceEpoch,
                date: dateStr,
                batteryPercentage: batteryLevel,
                address: ipLocation['address'] as String,
                gpsStatus: 'IP (Approx)',
              );
              await _dbService.saveLocation(mobile, location);
            }
          } catch (e) {
            debugPrint('[FamilyTracker] IP location push error: $e');
          }
        }
      });
    }

    debugPrint(
        '[FamilyTracker] Continuous background tracking started for: $mobile');
  }

  // Stop Continuous Tracking
  void stopContinuousTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _serviceStatusSubscription?.cancel();
    _serviceStatusSubscription = null;
  }
}
