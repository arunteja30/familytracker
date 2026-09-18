import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_family_tracker/models/geofence_place_model.dart';

void main() {
  group('GeofencePlaceModel Tests', () {
    test('Place applies to all members when targetMemberMobile is empty or all', () {
      final sharedPlace = GeofencePlaceModel(
        id: 'place_1',
        familyName: 'Smith',
        name: 'Home',
        latitude: 37.7749,
        longitude: -122.4194,
        targetMemberMobile: '',
      );

      expect(sharedPlace.isForAllMembers, isTrue);
      expect(sharedPlace.appliesToMember('+919876543210'), isTrue);
      expect(sharedPlace.appliesToMember('9876543210'), isTrue);
    });

    test('Place applies to specific assigned member', () {
      final childSchoolPlace = GeofencePlaceModel(
        id: 'place_2',
        familyName: 'Smith',
        name: 'High School',
        latitude: 37.7800,
        longitude: -122.4200,
        targetMemberMobile: '+919876543210',
        targetMemberName: 'Alex',
      );

      expect(childSchoolPlace.isForAllMembers, isFalse);
      expect(childSchoolPlace.appliesToMember('9876543210'), isTrue);
      expect(childSchoolPlace.appliesToMember('1112223334'), isFalse);
    });

    test('Schedule time-window evaluations', () {
      final scheduledPlace = GeofencePlaceModel(
        id: 'place_3',
        familyName: 'Smith',
        name: 'School Hours',
        latitude: 37.7800,
        longitude: -122.4200,
        isScheduleActive: true,
        startHour: 8,
        startMinute: 0,
        endHour: 15,
        endMinute: 0,
        activeDays: [1, 2, 3, 4, 5], // Monday - Friday
      );

      // Wednesday at 10:00 AM (Within window) -> Active
      final wednesdayMorning = DateTime(2026, 9, 16, 10, 0); // 2026-09-16 is Wednesday (weekday 3)
      expect(scheduledPlace.isCurrentlyActiveInSchedule(wednesdayMorning), isTrue);

      // Wednesday at 18:00 PM (Outside window) -> Inactive
      final wednesdayEvening = DateTime(2026, 9, 16, 18, 0);
      expect(scheduledPlace.isCurrentlyActiveInSchedule(wednesdayEvening), isFalse);

      // Sunday at 10:00 AM (Weekend) -> Inactive
      final sundayMorning = DateTime(2026, 9, 20, 10, 0); // 2026-09-20 is Sunday (weekday 7)
      expect(scheduledPlace.isCurrentlyActiveInSchedule(sundayMorning), isFalse);
    });

    test('JSON serialization & deserialization preserves schedule and coordinates', () {
      final original = GeofencePlaceModel(
        id: 'place_test',
        familyName: 'TestFamily',
        name: 'Office',
        category: PlaceCategory.work,
        latitude: 12.9716,
        longitude: 77.5946,
        radiusMeters: 250.0,
        isScheduleActive: true,
        startHour: 9,
        startMinute: 30,
        endHour: 18,
        endMinute: 30,
        activeDays: [1, 2, 3, 4, 5],
      );

      final json = original.toJson();
      final reconstructed = GeofencePlaceModel.fromJson(json);

      expect(reconstructed.id, original.id);
      expect(reconstructed.name, original.name);
      expect(reconstructed.category, PlaceCategory.work);
      expect(reconstructed.latitude, original.latitude);
      expect(reconstructed.longitude, original.longitude);
      expect(reconstructed.radiusMeters, 250.0);
      expect(reconstructed.isScheduleActive, isTrue);
      expect(reconstructed.startHour, 9);
      expect(reconstructed.startMinute, 30);
      expect(reconstructed.endHour, 18);
      expect(reconstructed.endMinute, 30);
      expect(reconstructed.activeDays, [1, 2, 3, 4, 5]);
    });
  });
}
