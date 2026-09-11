import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class IpLocationService {
  // Fetch approximate coarse location based on current IP address (Cellular or Wi-Fi)
  static Future<Map<String, dynamic>?> getCoarseIpLocation() async {
    // 1. Primary: ip-api.com
    try {
      final response = await http
          .get(
            Uri.parse(
                'http://ip-api.com/json?fields=status,message,country,regionName,city,lat,lon,query'),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['status'] == 'success') {
          final lat = (data['lat'] as num?)?.toDouble() ?? 0.0;
          final lon = (data['lon'] as num?)?.toDouble() ?? 0.0;
          final city = data['city']?.toString() ?? '';
          final region = data['regionName']?.toString() ?? '';
          final country = data['country']?.toString() ?? '';

          if (lat != 0.0 && lon != 0.0) {
            final parts = [city, region, country].where((s) => s.isNotEmpty);
            final address =
                '${parts.join(', ')} (Approximate IP Location - GPS is OFF)';

            debugPrint(
                '[IpLocationService] IP Location resolved from ip-api: ($lat, $lon) - $address');
            return {
              'lat': lat,
              'lon': lon,
              'city': city,
              'region': region,
              'country': country,
              'address': address,
            };
          }
        }
      }
    } catch (e) {
      debugPrint('[IpLocationService] ip-api failed: $e');
    }

    // 2. Fallback: ipapi.co
    try {
      final response = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map &&
            data.containsKey('latitude') &&
            data.containsKey('longitude')) {
          final lat = (data['latitude'] as num?)?.toDouble() ?? 0.0;
          final lon = (data['longitude'] as num?)?.toDouble() ?? 0.0;
          final city = data['city']?.toString() ?? '';
          final region = data['region']?.toString() ?? '';
          final country = data['country_name']?.toString() ?? '';

          if (lat != 0.0 && lon != 0.0) {
            final parts = [city, region, country].where((s) => s.isNotEmpty);
            final address =
                '${parts.join(', ')} (Approximate IP Location - GPS is OFF)';

            debugPrint(
                '[IpLocationService] IP Location resolved from ipapi.co: ($lat, $lon) - $address');
            return {
              'lat': lat,
              'lon': lon,
              'city': city,
              'region': region,
              'country': country,
              'address': address,
            };
          }
        }
      }
    } catch (e) {
      debugPrint('[IpLocationService] ipapi.co fallback failed: $e');
    }

    return null;
  }
}
