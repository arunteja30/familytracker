import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/family_member_model.dart';
import '../models/geofence_place_model.dart';
import '../models/location_details_model.dart';
import '../models/place_event_model.dart';
import 'database_service.dart';
import 'notification_service.dart';

/// Intelligent Geofence & Safe Place Evaluation Engine
///
/// Evaluates live member movements against registered Safe Places (Home, School, Work, etc.)
/// and triggers arrival/departure notifications and RTDB activity logs with hysteresis filtering.
class GeofenceService {
  static final GeofenceService _instance = GeofenceService._internal();
  factory GeofenceService() => _instance;
  GeofenceService._internal();

  final DatabaseService _dbService = DatabaseService();

  // In-memory state tracking: key is "$memberMobile-$placeId" -> bool isInside
  static final Map<String, bool> _memberPlaceStates = {};

  // Last event timestamp to prevent duplicate rapid triggers within 60s
  static final Map<String, int> _lastEventTimestamps = {};

  // Hysteresis buffer in meters (distance must exceed radius + buffer to trigger exit)
  static const double _hysteresisBufferMeters = 25.0;

  /// Evaluate a member's new location against all configured family safe places
  Future<void> evaluateMemberLocation({
    required FamilyMemberModel member,
    required LocationDetailsModel location,
    required List<GeofencePlaceModel> places,
  }) async {
    if (location.latitude == 0.0 && location.longitude == 0.0) return;
    if (member.mobile.isEmpty || places.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    for (final place in places) {
      if (place.latitude == 0.0 && place.longitude == 0.0) continue;

      final distance = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        place.latitude,
        place.longitude,
      );

      final stateKey = '${member.mobile.trim()}_${place.id.trim()}';
      final previousState = _memberPlaceStates[stateKey];
      final isCurrentlyInside = distance <= place.radiusMeters;
      final isCurrentlyOutside = distance > (place.radiusMeters + _hysteresisBufferMeters);

      // Check for Arrival (Outside -> Inside)
      if (isCurrentlyInside && (previousState == null || previousState == false)) {
        _memberPlaceStates[stateKey] = true;

        final lastEvent = _lastEventTimestamps['${stateKey}_entered'] ?? 0;
        if (now - lastEvent > 60 * 1000) {
          _lastEventTimestamps['${stateKey}_entered'] = now;

          if (place.notifyOnEntry) {
            debugPrint('[GeofenceService] 🏠 ARRIVAL: ${member.name} entered ${place.name} (dist: ${distance.toStringAsFixed(1)}m)');

            // 1. Dispatch local heads-up notification
            await NotificationService.showPlaceAlert(
              memberName: member.name,
              placeName: place.name,
              isArrival: true,
              familyName: member.familyName,
            );

            // 2. Log event to Firebase RTDB for live timeline
            await _dbService.logPlaceEvent(
              PlaceEventModel(
                id: '',
                familyName: member.familyName,
                placeId: place.id,
                placeName: place.name,
                memberName: member.name,
                memberMobile: member.mobile,
                eventType: 'entered',
                timestamp: now,
              ),
            );
          }
        }
      }
      // Check for Departure (Inside -> Outside)
      else if (isCurrentlyOutside && previousState == true) {
        _memberPlaceStates[stateKey] = false;

        final lastEvent = _lastEventTimestamps['${stateKey}_left'] ?? 0;
        if (now - lastEvent > 60 * 1000) {
          _lastEventTimestamps['${stateKey}_left'] = now;

          if (place.notifyOnExit) {
            debugPrint('[GeofenceService] 🚗 DEPARTURE: ${member.name} left ${place.name} (dist: ${distance.toStringAsFixed(1)}m)');

            // 1. Dispatch local heads-up notification
            await NotificationService.showPlaceAlert(
              memberName: member.name,
              placeName: place.name,
              isArrival: false,
              familyName: member.familyName,
            );

            // 2. Log event to Firebase RTDB for live timeline
            await _dbService.logPlaceEvent(
              PlaceEventModel(
                id: '',
                familyName: member.familyName,
                placeId: place.id,
                placeName: place.name,
                memberName: member.name,
                memberMobile: member.mobile,
                eventType: 'left',
                timestamp: now,
              ),
            );
          }
        }
      }
    }
  }

  /// Check current status of a member relative to all places (returns list of places where member is currently inside)
  List<GeofencePlaceModel> getPlacesMemberIsInside({
    required String memberMobile,
    required List<GeofencePlaceModel> places,
  }) {
    final List<GeofencePlaceModel> inside = [];
    for (final p in places) {
      final key = '${memberMobile.trim()}_${p.id.trim()}';
      if (_memberPlaceStates[key] == true) {
        inside.add(p);
      }
    }
    return inside;
  }
}
