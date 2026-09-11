import 'dart:collection';
import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Production-Grade Hybrid Geocoding Engine with Firebase Cloud Cache
///
/// Hierarchy / Architecture:
/// 1. Level 0A: Fast In-Memory LRU Cache (500 items, ~11m quantization, 0ms latency, $0 cost)
/// 2. Level 0B: Local Spatial Proximity Check (≤ 40m radius match against known places)
/// 3. Level 0C: Persistent Disk Storage (SharedPreferences offline cache across reboots)
/// 4. Level 1: Shared Firebase Cloud Geo-Cache (`geocache/{safeKey}` shared across all family members)
/// 5. Level 2: Google Maps Geocoding API (High-accuracy primary provider)
/// 6. Level 3: OpenStreetMap Nominatim (Backup 100% Free / Libre provider)
/// 7. Level 4: BigDataCloud Reverse Geocoder (Zero-config client fallback)
/// 8. Level 5: Graceful Lat/Lng fallback representation
class GeocodingService {
  static const int _maxCacheSize = 500;
  static const String _prefKey = 'ft_persistent_geocache_v1';

  // LinkedHashMap maintains insertion order for true LRU eviction
  static final LinkedHashMap<String, String> _cache =
      LinkedHashMap<String, String>();

  // In-flight request deduplication map to prevent redundant concurrent network calls
  static final Map<String, Future<String>> _inFlightRequests = {};

  static bool _isLoadedFromDisk = false;

  // Google Geocoding REST API Key (Dynamically loaded from environment or local.properties)
  static const String _googleGeocodingApiKey = String.fromEnvironment(
    'GEOCODING_API_KEY',
    defaultValue: String.fromEnvironment(
      'MAPS_API_KEY',
      defaultValue: 'AIzaSyBbI2vk6FrUB7xPCKROW1wP__xsaUn-JiA',
    ),
  );

  /// Convert coordinates into a Firebase RTDB sanitized key
  static String _toFirebaseKey(double lat, double lng) {
    final latStr = lat.toStringAsFixed(4).replaceAll('.', '_').replaceAll('-', 'neg_');
    final lngStr = lng.toStringAsFixed(4).replaceAll('.', '_').replaceAll('-', 'neg_');
    return '${latStr}__$lngStr';
  }

  /// Initialize and load persistent cache from disk, then async sync latest from Firebase
  static Future<void> _ensureCacheLoaded() async {
    if (_isLoadedFromDisk) return;
    _isLoadedFromDisk = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final decoded = json.decode(jsonStr);
        if (decoded is Map<String, dynamic>) {
          decoded.forEach((k, v) {
            if (v is String && v.isNotEmpty) {
              _cache[k] = v;
            }
          });
          debugPrint(
              '[GeocodingService] Loaded ${_cache.length} persistent geocoded locations from disk.');
        }
      }
    } catch (e) {
      debugPrint('[GeocodingService] Error loading cache from disk: $e');
    }

    // Pre-warm / sync shared Firebase Cloud Geo-Cache to local storage in background
    syncCloudCacheToLocal();
  }

  /// Download and sync all available shared geocache from Firebase RTDB to local disk for offline resilience
  static Future<void> syncCloudCacheToLocal() async {
    try {
      final ref = FirebaseDatabase.instance.ref('geocache').limitToLast(500);
      final snapshot = await ref.get().timeout(const Duration(seconds: 4));
      if (snapshot.exists && snapshot.value is Map) {
        final data = snapshot.value as Map;
        int count = 0;
        data.forEach((k, v) {
          String? address;
          String? cacheKey;
          if (v is Map) {
            address = v['address']?.toString();
            final lat = v['lat'];
            final lng = v['lng'];
            if (lat is num && lng is num) {
              cacheKey =
                  '${lat.toDouble().toStringAsFixed(4)}_${lng.toDouble().toStringAsFixed(4)}';
            }
          } else if (v is String) {
            address = v;
          }

          if (cacheKey == null && k is String) {
            // Convert sanitized 17_4456__78_3456 back to 17.4456_78.3456
            final parts = k.split('__');
            if (parts.length == 2) {
              final latPart =
                  parts[0].replaceAll('neg_', '-').replaceAll('_', '.');
              final lngPart =
                  parts[1].replaceAll('neg_', '-').replaceAll('_', '.');
              cacheKey = '${latPart}_$lngPart';
            }
          }

          if (cacheKey != null && address != null && address.trim().isNotEmpty) {
            _cache[cacheKey] = address.trim();
            count++;
          }
        });

        if (count > 0) {
          _persistCacheToDisk();
          debugPrint(
              '[GeocodingService] 🚀 Synced $count cloud geocache entries from Firebase to local offline storage.');
        }
      }
    } catch (e) {
      debugPrint('[GeocodingService] Cloud geocache sync exception: $e');
    }
  }

  /// Save memory cache to persistent disk storage
  static Future<void> _persistCacheToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = json.encode(_cache);
      await prefs.setString(_prefKey, jsonStr);
    } catch (e) {
      debugPrint('[GeocodingService] Error saving cache to disk: $e');
    }
  }

  static void _addToCache(String key, String address) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first); // Evict oldest entry
    }
    _cache[key] = address;
    _persistCacheToDisk();
  }

  /// Check if a coordinate is within [maxDistanceMeters] (default 40m) of any locally cached location
  static String? _findNearbyCachedAddress(
      double latitude, double longitude, {double maxDistanceMeters = 40.0}) {
    for (final entry in _cache.entries) {
      final parts = entry.key.split('_');
      if (parts.length == 2) {
        final cachedLat = double.tryParse(parts[0]);
        final cachedLng = double.tryParse(parts[1]);
        if (cachedLat != null && cachedLng != null) {
          final distance = Geolocator.distanceBetween(
            latitude,
            longitude,
            cachedLat,
            cachedLng,
          );
          if (distance <= maxDistanceMeters) {
            return entry.value;
          }
        }
      }
    }
    return null;
  }

  /// Query the shared Firebase Cloud Geo-Cache with a fast 1500ms timeout
  static Future<String?> _fetchFromFirebaseCloudCache(String dbKey) async {
    try {
      final ref = FirebaseDatabase.instance.ref('geocache/$dbKey');
      final snapshot =
          await ref.get().timeout(const Duration(milliseconds: 1500));

      if (snapshot.exists && snapshot.value != null) {
        final val = snapshot.value;
        if (val is String && val.trim().isNotEmpty) {
          return val.trim();
        } else if (val is Map) {
          final addr = val['address']?.toString() ?? '';
          if (addr.trim().isNotEmpty) {
            return addr.trim();
          }
        }
      }
    } catch (e) {
      debugPrint('[GeocodingService] Firebase cloud cache lookup bypassed: $e');
    }
    return null;
  }

  /// Asynchronously upload a newly resolved address to Firebase without blocking UI
  static void _uploadToFirebaseCloudCache(
      String dbKey, String address, double lat, double lng) {
    try {
      final ref = FirebaseDatabase.instance.ref('geocache/$dbKey');
      ref.set({
        'address': address,
        'lat': lat,
        'lng': lng,
        'updatedAt': ServerValue.timestamp,
      }).catchError((e) {
        debugPrint('[GeocodingService] Cloud geocache write failed: $e');
      });
    } catch (e) {
      debugPrint('[GeocodingService] Cloud geocache upload exception: $e');
    }
  }

  /// Alias for getAddressFromCoordinates
  static Future<String> getAddress(double latitude, double longitude) =>
      getAddressFromCoordinates(latitude, longitude);

  /// Reverse geocode latitude and longitude with smart multi-tier spatial & cloud caching
  static Future<String> getAddressFromCoordinates(
      double latitude, double longitude) async {
    if (latitude == 0.0 && longitude == 0.0) {
      return 'No GPS fix';
    }

    await _ensureCacheLoaded();

    // Cache key rounded to ~11 meters (4 decimal places)
    final cacheKey =
        '${latitude.toStringAsFixed(4)}_${longitude.toStringAsFixed(4)}';

    // 1. Level 0A: Instant Local Exact LRU Cache Hit (0ms, $0 cost)
    if (_cache.containsKey(cacheKey)) {
      final val = _cache.remove(cacheKey)!;
      _cache[cacheKey] = val; // Move to most recently used
      return val;
    }

    // 2. Level 0B: Local Spatial Proximity Check (≤ 40m radius match)
    final nearbyAddress = _findNearbyCachedAddress(latitude, longitude,
        maxDistanceMeters: 40.0);
    if (nearbyAddress != null && nearbyAddress.isNotEmpty) {
      _addToCache(cacheKey, nearbyAddress);
      return nearbyAddress;
    }

    // 3. In-flight request deduplication (prevents duplicate concurrent calls)
    if (_inFlightRequests.containsKey(cacheKey)) {
      return await _inFlightRequests[cacheKey]!;
    }

    final future = _fetchAddressHybrid(latitude, longitude, cacheKey);
    _inFlightRequests[cacheKey] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _inFlightRequests.remove(cacheKey);
    }
  }

  static Future<String> _fetchAddressHybrid(
      double latitude, double longitude, String cacheKey) async {
    final dbKey = _toFirebaseKey(latitude, longitude);

    // -------------------------------------------------------------
    // Level 1: Shared Firebase Realtime Database Cloud Cache
    // -------------------------------------------------------------
    final cloudAddress = await _fetchFromFirebaseCloudCache(dbKey);
    if (cloudAddress != null && cloudAddress.isNotEmpty) {
      debugPrint('[GeocodingService] ⚡ Shared Cloud Cache HIT from Firebase for $cacheKey ($cloudAddress)');
      _addToCache(cacheKey, cloudAddress);
      return cloudAddress;
    }

    // -------------------------------------------------------------
    // Level 2: Google Maps Geocoding API (Primary Provider)
    // -------------------------------------------------------------
    if (_googleGeocodingApiKey.isNotEmpty) {
      try {
        final googleUrl = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=$latitude,$longitude&key=$_googleGeocodingApiKey',
        );

        final response =
            await http.get(googleUrl).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data is Map &&
              data['status'] == 'OK' &&
              data['results'] is List &&
              (data['results'] as List).isNotEmpty) {
            final firstResult = data['results'][0];
            final formattedAddress =
                firstResult['formatted_address']?.toString() ?? '';

            if (formattedAddress.isNotEmpty) {
              final parts = formattedAddress.split(', ');
              final shortAddress = parts.length > 4
                  ? parts.sublist(0, 4).join(', ')
                  : formattedAddress;

              _addToCache(cacheKey, shortAddress);
              _uploadToFirebaseCloudCache(dbKey, shortAddress, latitude, longitude);
              return shortAddress;
            }
          }
        }
      } catch (e) {
        debugPrint(
            '[GeocodingService] Google Geocoding failed/timed out. Switching to OSM backup: $e');
      }
    }

    // -------------------------------------------------------------
    // Level 3: OpenStreetMap (Nominatim) - Backup Provider
    // -------------------------------------------------------------
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$latitude&lon=$longitude&zoom=18&addressdetails=1',
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'FamilyTrackerApp/1.0 (familytracker.safety.app)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data.containsKey('display_name')) {
          final displayName = data['display_name'].toString();
          final parts = displayName.split(', ');
          final shortAddress = parts.length > 4
              ? parts.sublist(0, 4).join(', ')
              : displayName;

          if (shortAddress.trim().isNotEmpty) {
            _addToCache(cacheKey, shortAddress);
            _uploadToFirebaseCloudCache(dbKey, shortAddress, latitude, longitude);
            return shortAddress;
          }
        }
      }
    } catch (e) {
      debugPrint('[GeocodingService] OSM lookup backup failed: $e');
    }

    // -------------------------------------------------------------
    // Level 4: BigDataCloud Client Reverse Geocoding (Free Tier)
    // -------------------------------------------------------------
    try {
      final fallbackUrl = Uri.parse(
        'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$latitude&longitude=$longitude&localityLanguage=en',
      );

      final response =
          await http.get(fallbackUrl).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map) {
          final locality = data['locality']?.toString() ?? '';
          final city = data['city']?.toString() ??
              data['principalSubdivision']?.toString() ??
              '';
          final country = data['countryName']?.toString() ?? '';

          final addressList =
              [locality, city, country].where((s) => s.isNotEmpty).toList();
          if (addressList.isNotEmpty) {
            final formatted = addressList.join(', ');
            _addToCache(cacheKey, formatted);
            _uploadToFirebaseCloudCache(dbKey, formatted, latitude, longitude);
            return formatted;
          }
        }
      }
    } catch (_) {}

    // -------------------------------------------------------------
    // Level 5: Graceful Coordinate String Fallback
    // -------------------------------------------------------------
    final fallback =
        'Lat: ${latitude.toStringAsFixed(4)}, Lon: ${longitude.toStringAsFixed(4)}';
    _addToCache(cacheKey, fallback);
    return fallback;
  }
}
