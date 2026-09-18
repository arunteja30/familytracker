import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/family_member_model.dart';
import '../models/geofence_place_model.dart';
import '../models/location_details_model.dart';
import '../models/place_event_model.dart';
import '../utils/phone_utils.dart';
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

  // In-memory state tracking: key is "${normalizedMobile}_${placeId}" -> bool isInside
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

    // Filter places applicable to this member (either 'Everyone' or specifically assigned to this member)
    final memberPlaces = places.where((p) => p.appliesToMember(member.mobile)).toList();
    if (memberPlaces.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final normalizedMobile = PhoneUtils.normalize(member.mobile);

    for (final place in memberPlaces) {
      if (place.latitude == 0.0 && place.longitude == 0.0) continue;

      final distance = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        place.latitude,
        place.longitude,
      );

      final stateKey = '${normalizedMobile}_${place.id.trim()}';
      final previousState = _memberPlaceStates[stateKey];
      final isCurrentlyInside = distance <= place.radiusMeters;
      final isCurrentlyOutside = distance > (place.radiusMeters + _hysteresisBufferMeters);

      // Baseline initialization on first check for this member-place pair
      if (previousState == null) {
        _memberPlaceStates[stateKey] = isCurrentlyInside;
        continue;
      }

      final effectiveFamily = member.familyName.isNotEmpty ? member.familyName : place.familyName;
      final effectiveName = member.name.isNotEmpty ? member.name : PhoneUtils.formatDisplay(member.mobile);

      // Check for Arrival (Outside -> Inside)
      if (isCurrentlyInside && previousState == false) {
        _memberPlaceStates[stateKey] = true;

        final lastEvent = _lastEventTimestamps['${stateKey}_entered'] ?? 0;
        if (now - lastEvent > 60 * 1000) {
          _lastEventTimestamps['${stateKey}_entered'] = now;

          if (place.notifyOnEntry) {
            debugPrint('[GeofenceService] 🏠 ARRIVAL: $effectiveName entered ${place.name} (dist: ${distance.toStringAsFixed(1)}m)');

            // 1. Dispatch local heads-up notification
            await NotificationService.showPlaceAlert(
              memberName: effectiveName,
              placeName: place.name,
              isArrival: true,
              familyName: effectiveFamily,
            );

            // 2. Log event to Firebase RTDB for live timeline
            await _dbService.logPlaceEvent(
              PlaceEventModel(
                id: '',
                familyName: effectiveFamily,
                placeId: place.id,
                placeName: place.name,
                memberName: effectiveName,
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
            debugPrint('[GeofenceService] 🚗 DEPARTURE: $effectiveName left ${place.name} (dist: ${distance.toStringAsFixed(1)}m)');

            // 1. Dispatch local heads-up notification
            await NotificationService.showPlaceAlert(
              memberName: effectiveName,
              placeName: place.name,
              isArrival: false,
              familyName: effectiveFamily,
            );

            // 2. Log event to Firebase RTDB for live timeline
            await _dbService.logPlaceEvent(
              PlaceEventModel(
                id: '',
                familyName: effectiveFamily,
                placeId: place.id,
                placeName: place.name,
                memberName: effectiveName,
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
    final memberPlaces = places.where((p) => p.appliesToMember(memberMobile)).toList();
    final normalizedMobile = PhoneUtils.normalize(memberMobile);
    for (final p in memberPlaces) {
      final key = '${normalizedMobile}_${p.id.trim()}';
      if (_memberPlaceStates[key] == true) {
        inside.add(p);
      }
    }
    return inside;
  }
}
