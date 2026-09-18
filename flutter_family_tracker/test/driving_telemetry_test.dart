import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_family_tracker/models/location_details_model.dart';

void main() {
  group('Driving Telemetry & LocationDetailsModel Tests', () {
    test('isMoving returns true when speed >= 5 km/h', () {
      final stationary = LocationDetailsModel(
        latitude: 37.7749,
        longitude: -122.4194,
        speedKmh: 2.1,
      );
      expect(stationary.isMoving, isFalse);

      final driving = LocationDetailsModel(
        latitude: 37.7749,
        longitude: -122.4194,
        speedKmh: 45.6,
      );
      expect(driving.isMoving, isTrue);
      expect(driving.formattedSpeed, '46 km/h');
    });

    test('JSON serialization preserves speed and heading', () {
      final loc = LocationDetailsModel(
        latitude: 12.9716,
        longitude: 77.5946,
        timeStamp: 1726000000000,
        batteryPercentage: 88,
        address: 'MG Road, Bangalore',
        speedKmh: 62.4,
        heading: 180.5,
      );

      final json = loc.toJson();
      final parsed = LocationDetailsModel.fromJson(json);

      expect(parsed.latitude, 12.9716);
      expect(parsed.longitude, 77.5946);
      expect(parsed.speedKmh, 62.4);
      expect(parsed.heading, 180.5);
      expect(parsed.batteryPercentage, 88);
      expect(parsed.isMoving, isTrue);
    });
  });
}
