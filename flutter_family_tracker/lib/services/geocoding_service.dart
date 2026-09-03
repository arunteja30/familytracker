import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class GeocodingService {
  static final Map<String, String> _cache = {};

  // Reverse geocode latitude and longitude to street address
  static Future<String> getAddressFromCoordinates(
      double latitude, double longitude) async {
    if (latitude == 0.0 && longitude == 0.0) {
      return 'No GPS fix';
    }

    // Cache key rounded to ~30 meters (4 decimals)
    final cacheKey =
        '${latitude.toStringAsFixed(4)}_${longitude.toStringAsFixed(4)}';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    try {
      // 1. Try OpenStreetMap Nominatim reverse geocoding
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$latitude&lon=$longitude&zoom=18&addressdetails=1',
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'FamilyTrackerApp/1.0 (familytracker.safety.app)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data.containsKey('display_name')) {
          final displayName = data['display_name'].toString();
          final parts = displayName.split(', ');
          // Take the most relevant 3-4 components for a concise, clean address
          final shortAddress = parts.length > 4
              ? parts.sublist(0, 4).join(', ')
              : displayName;

          _cache[cacheKey] = shortAddress;
          return shortAddress;
        }
      }
    } catch (_) {}

    try {
      // 2. Fallback: BigDataCloud client reverse geocoding (no API key needed)
      final fallbackUrl = Uri.parse(
        'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$latitude&longitude=$longitude&localityLanguage=en',
      );

      final response = await http.get(fallbackUrl).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map) {
          final locality = data['locality']?.toString() ?? '';
          final city = data['city']?.toString() ?? data['principalSubdivision']?.toString() ?? '';
          final country = data['countryName']?.toString() ?? '';

          final addressList = [locality, city, country].where((s) => s.isNotEmpty).toList();
          if (addressList.isNotEmpty) {
            final formatted = addressList.join(', ');
            _cache[cacheKey] = formatted;
            return formatted;
          }
        }
      }
    } catch (_) {}

    // Fallback format
    final fallback =
        'Lat: ${latitude.toStringAsFixed(4)}, Lon: ${longitude.toStringAsFixed(4)}';
    _cache[cacheKey] = fallback;
    return fallback;
  }
}
