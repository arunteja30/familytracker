import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:intl/intl.dart';
import '../models/location_details_model.dart';
import 'database_service.dart';

class LocationService {
  final Battery _battery = Battery();
  final DatabaseService _dbService = DatabaseService();

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

  // Get Current Location & Battery Info
  Future<LocationDetailsModel?> getCurrentLocationDetails() async {
    try {
      final hasPermission = await checkPermission();
      if (!hasPermission) return null;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      final batteryLevel = await _battery.batteryLevel;
      final address = 'Lat: ${position.latitude.toStringAsFixed(4)}, Lon: ${position.longitude.toStringAsFixed(4)}';

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

  // Update Location for a User
  Future<void> updateAndPushLocation(String mobile) async {
    final location = await getCurrentLocationDetails();
    if (location != null && mobile.isNotEmpty) {
      await _dbService.saveLocation(mobile, location);
    }
  }
}
