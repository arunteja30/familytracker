import 'package:geolocator/geolocator.dart';

/// Utilities for calculating and displaying relative distances between family members
class ProximityUtils {
  /// Format distance in meters into human-friendly string (e.g. "Nearby", "450 m away", "2.3 km away")
  static String formatDistance(double distanceInMeters) {
    if (distanceInMeters.isNaN || distanceInMeters.isInfinite || distanceInMeters < 0) {
      return '';
    }
    if (distanceInMeters < 50) {
      return 'Nearby';
    }
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.round()} m away';
    }
    final km = distanceInMeters / 1000.0;
    if (km < 10) {
      return '${km.toStringAsFixed(1)} km away';
    }
    return '${km.round()} km away';
  }

  /// Calculate distance between two GPS coordinates in meters
  static double calculateDistanceMeters({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    if (lat1 == 0.0 && lng1 == 0.0) return -1;
    if (lat2 == 0.0 && lng2 == 0.0) return -1;
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }

  /// Formatted relative distance string between current user location and a target location
  static String getRelativeDistance({
    required double? userLat,
    required double? userLng,
    required double? targetLat,
    required double? targetLng,
  }) {
    if (userLat == null || userLng == null || targetLat == null || targetLng == null) {
      return '';
    }
    final meters = calculateDistanceMeters(
      lat1: userLat,
      lng1: userLng,
      lat2: targetLat,
      lng2: targetLng,
    );
    if (meters < 0) return '';
    return formatDistance(meters);
  }
}
