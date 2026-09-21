import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// Routing profile types supported by OpenStreetMap / OSRM
enum RouteProfile {
  bicycle,
  driving,
  foot,
  direct,
}

extension RouteProfileExtension on RouteProfile {
  String get label {
    switch (this) {
      case RouteProfile.bicycle:
        return 'Bike Roads (OSM)';
      case RouteProfile.driving:
        return 'Driving';
      case RouteProfile.foot:
        return 'Walking';
      case RouteProfile.direct:
        return 'Direct Path';
    }
  }

  String get icon {
    switch (this) {
      case RouteProfile.bicycle:
        return '🚲';
      case RouteProfile.driving:
        return '🚗';
      case RouteProfile.foot:
        return '🚶';
      case RouteProfile.direct:
        return '📏';
    }
  }
}

/// Result containing the resolved directional road polyline coordinates and metrics
class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final bool isSnappedToRoads;
  final RouteProfile profile;

  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.isSnappedToRoads,
    required this.profile,
  });

  double get distanceKm => distanceMeters / 1000.0;

  String get formattedDistance {
    if (distanceKm < 1.0) {
      return '${distanceMeters.toStringAsFixed(0)} m';
    }
    return '${distanceKm.toStringAsFixed(2)} km';
  }

  String get formattedDuration {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) {
      return '$minutes min';
    }
    final hours = minutes ~/ 60;
    final remainingMins = minutes % 60;
    return '${hours}h ${remainingMins}m';
  }
}

/// Production-Grade Routing Engine with OpenStreetMap & OSRM Directional Bike Road API
class RoutingService {
  static const int _maxCacheSize = 100;
  static final LinkedHashMap<String, RouteResult> _cache =
      LinkedHashMap<String, RouteResult>();

  // In-flight request deduplication map
  static final Map<String, Future<RouteResult>> _inFlightRequests = {};

  /// Get directional route following bike roads or other profiles
  static Future<RouteResult> getRoute({
    required List<LatLng> waypoints,
    RouteProfile profile = RouteProfile.bicycle,
  }) async {
    // 1. Filter out invalid/zero coordinates
    final validPoints = waypoints
        .where((p) => p.latitude != 0.0 && p.longitude != 0.0)
        .toList();

    if (validPoints.isEmpty) {
      return RouteResult(
        points: const [],
        distanceMeters: 0.0,
        durationSeconds: 0.0,
        isSnappedToRoads: false,
        profile: profile,
      );
    }

    if (validPoints.length == 1) {
      return RouteResult(
        points: validPoints,
        distanceMeters: 0.0,
        durationSeconds: 0.0,
        isSnappedToRoads: false,
        profile: profile,
      );
    }

    // Direct profile bypasses network API
    if (profile == RouteProfile.direct) {
      return _buildDirectRoute(validPoints, profile);
    }

    // 2. Simplify points to remove consecutive GPS points within ~3 meters
    final simplifiedPoints = _filterDeduplicatedPoints(validPoints);

    // 3. Cache lookup
    final cacheKey = _generateCacheKey(simplifiedPoints, profile);
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache.remove(cacheKey)!;
      _cache[cacheKey] = cached; // Move to most recently used
      return cached;
    }

    // 4. In-flight request deduplication
    if (_inFlightRequests.containsKey(cacheKey)) {
      return await _inFlightRequests[cacheKey]!;
    }

    final future = _fetchRouteInternal(simplifiedPoints, profile, cacheKey);
    _inFlightRequests[cacheKey] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _inFlightRequests.remove(cacheKey);
    }
  }

  /// Remove redundant consecutive points closer than 3 meters to prevent route API noise
  static List<LatLng> _filterDeduplicatedPoints(List<LatLng> points) {
    if (points.length <= 2) return points;
    final result = <LatLng>[points.first];

    for (int i = 1; i < points.length; i++) {
      final current = points[i];
      final prev = result.last;
      final dist = Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        current.latitude,
        current.longitude,
      );

      // Keep point if further than 3m, or if it's the very last destination point
      if (dist >= 3.0 || i == points.length - 1) {
        result.add(current);
      }
    }
    return result;
  }

  static String _generateCacheKey(List<LatLng> points, RouteProfile profile) {
    final sb = StringBuffer('${profile.name}_');
    for (final p in points) {
      sb.write('${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)};');
    }
    return sb.toString();
  }

  static void _addToCache(String key, RouteResult result) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = result;
  }

  static Future<RouteResult> _fetchRouteInternal(
    List<LatLng> points,
    RouteProfile profile,
    String cacheKey,
  ) async {
    try {
      // Chunk coordinates into batches of max 15 points to avoid URL length / server limits
      const int batchSize = 15;
      final List<LatLng> fullRoutePoints = [];
      double totalDistance = 0.0;
      double totalDuration = 0.0;
      bool anySegmentSnapped = false;

      for (int i = 0; i < points.length - 1; i += (batchSize - 1)) {
        final end = (i + batchSize < points.length) ? i + batchSize : points.length;
        final subPoints = points.sublist(i, end);
        if (subPoints.length < 2) break;

        final segmentResult = await _queryRoutingApi(subPoints, profile);
        if (segmentResult != null && segmentResult.points.isNotEmpty) {
          anySegmentSnapped = true;
          totalDistance += segmentResult.distanceMeters;
          totalDuration += segmentResult.durationSeconds;

          if (fullRoutePoints.isNotEmpty && segmentResult.points.isNotEmpty) {
            // Avoid duplicate point at segment junctions
            fullRoutePoints.addAll(segmentResult.points.skip(1));
          } else {
            fullRoutePoints.addAll(segmentResult.points);
          }
        } else {
          // Fallback for this segment: add original straight waypoints
          if (fullRoutePoints.isNotEmpty) {
            fullRoutePoints.addAll(subPoints.skip(1));
          } else {
            fullRoutePoints.addAll(subPoints);
          }
          // Calculate direct Euclidean distances
          for (int j = 0; j < subPoints.length - 1; j++) {
            totalDistance += Geolocator.distanceBetween(
              subPoints[j].latitude,
              subPoints[j].longitude,
              subPoints[j + 1].latitude,
              subPoints[j + 1].longitude,
            );
          }
        }
      }

      if (fullRoutePoints.isNotEmpty) {
        final result = RouteResult(
          points: fullRoutePoints,
          distanceMeters: totalDistance,
          durationSeconds: totalDuration,
          isSnappedToRoads: anySegmentSnapped,
          profile: profile,
        );
        _addToCache(cacheKey, result);
        return result;
      }
    } catch (e) {
      debugPrint('[RoutingService] Directional routing failed, falling back to direct path: $e');
    }

    final fallback = _buildDirectRoute(points, profile);
    _addToCache(cacheKey, fallback);
    return fallback;
  }

  /// Primary and fallback OpenStreetMap / OSRM API endpoints for bike & road routing
  static Future<RouteResult?> _queryRoutingApi(
    List<LatLng> waypoints,
    RouteProfile profile,
  ) async {
    // Build coordinate string "{lng},{lat};{lng},{lat}"
    final coords = waypoints
        .map((p) => '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}')
        .join(';');

    // 1. Primary endpoint: OSRM Public Bicycle Server
    if (profile == RouteProfile.bicycle) {
      final osrmBikeUrl =
          'https://router.project-osrm.org/route/v1/bicycle/$coords?overview=full&geometries=geojson';
      final res = await _executeRouteHttp(osrmBikeUrl, profile);
      if (res != null) return res;

      // 2. Secondary endpoint: OpenStreetMap Germany Bike Routing
      final osmBikeUrl =
          'https://routing.openstreetmap.de/routed-bike/route/v1/driving/$coords?overview=full&geometries=geojson';
      final res2 = await _executeRouteHttp(osmBikeUrl, profile);
      if (res2 != null) return res2;
    } else if (profile == RouteProfile.foot) {
      final osmFootUrl =
          'https://routing.openstreetmap.de/routed-foot/route/v1/driving/$coords?overview=full&geometries=geojson';
      final res = await _executeRouteHttp(osmFootUrl, profile);
      if (res != null) return res;
    }

    // 3. Fallback endpoint: OSRM Driving Server
    final osrmDrivingUrl =
        'https://router.project-osrm.org/route/v1/driving/$coords?overview=full&geometries=geojson';
    return await _executeRouteHttp(osrmDrivingUrl, profile);
  }

  static Future<RouteResult?> _executeRouteHttp(
    String urlString,
    RouteProfile profile,
  ) async {
    try {
      final url = Uri.parse(urlString);
      final headers = <String, String>{
        'Accept': 'application/json',
      };
      // User-Agent is forbidden in Web browsers by W3C specification
      if (!kIsWeb) {
        headers['User-Agent'] = 'FamilyTrackerApp/2.0 (familytracker.safety.app)';
      }

      final response = await http.get(
        url,
        headers: headers,
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map &&
            data['code'] == 'Ok' &&
            data['routes'] is List &&
            (data['routes'] as List).isNotEmpty) {
          final firstRoute = data['routes'][0];
          final distance = (firstRoute['distance'] as num?)?.toDouble() ?? 0.0;
          final duration = (firstRoute['duration'] as num?)?.toDouble() ?? 0.0;

          final geometry = firstRoute['geometry'];
          if (geometry is Map && geometry['coordinates'] is List) {
            final rawCoords = geometry['coordinates'] as List;
            final routePoints = <LatLng>[];

            for (final item in rawCoords) {
              if (item is List && item.length >= 2) {
                final lng = (item[0] as num).toDouble();
                final lat = (item[1] as num).toDouble();
                routePoints.add(LatLng(lat, lng));
              }
            }

            if (routePoints.isNotEmpty) {
              return RouteResult(
                points: routePoints,
                distanceMeters: distance,
                durationSeconds: duration,
                isSnappedToRoads: true,
                profile: profile,
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[RoutingService] Route query error for $urlString: $e');
    }
    return null;
  }

  static RouteResult _buildDirectRoute(List<LatLng> points, RouteProfile profile) {
    double totalDist = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      totalDist += Geolocator.distanceBetween(
        points[i].latitude,
        points[i].longitude,
        points[i + 1].latitude,
        points[i + 1].longitude,
      );
    }

    return RouteResult(
      points: List.from(points),
      distanceMeters: totalDist,
      durationSeconds: (totalDist / 4.16), // Approx 15 km/h walking/biking speed
      isSnappedToRoads: false,
      profile: profile,
    );
  }
}
