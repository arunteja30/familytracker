import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_family_tracker/utils/proximity_utils.dart';

void main() {
  group('ProximityUtils Tests', () {
    test('formatDistance handles small distances as Nearby', () {
      expect(ProximityUtils.formatDistance(0), 'Nearby');
      expect(ProximityUtils.formatDistance(49), 'Nearby');
    });

    test('formatDistance formats meters cleanly below 1km', () {
      expect(ProximityUtils.formatDistance(120), '120 m away');
      expect(ProximityUtils.formatDistance(850.4), '850 m away');
    });

    test('formatDistance formats km with 1 decimal below 10km', () {
      expect(ProximityUtils.formatDistance(1500), '1.5 km away');
      expect(ProximityUtils.formatDistance(3240), '3.2 km away');
    });

    test('formatDistance formats rounded km above 10km', () {
      expect(ProximityUtils.formatDistance(15400), '15 km away');
      expect(ProximityUtils.formatDistance(45800), '46 km away');
    });

    test('formatDistance handles invalid numbers safely', () {
      expect(ProximityUtils.formatDistance(-1), '');
      expect(ProximityUtils.formatDistance(double.nan), '');
    });

    test('getRelativeDistance returns empty if nulls provided', () {
      expect(
        ProximityUtils.getRelativeDistance(
          userLat: null,
          userLng: null,
          targetLat: 12.9716,
          targetLng: 77.5946,
        ),
        '',
      );
    });
  });
}
