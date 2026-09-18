import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_family_tracker/utils/phone_utils.dart';

void main() {
  group('PhoneUtils Tests', () {
    test('Phone normalization extracts standard 10-digit national number', () {
      expect(PhoneUtils.normalize('+91 98765-43210'), '9876543210');
      expect(PhoneUtils.normalize('(123) 456-7890'), '1234567890');
      expect(PhoneUtils.normalize(''), '');
    });

    test('isSame matches exact phone numbers', () {
      expect(PhoneUtils.isSame('9876543210', '9876543210'), isTrue);
    });

    test('isSame matches international and local representations with same 10-digit suffix', () {
      expect(PhoneUtils.isSame('+919876543210', '9876543210'), isTrue);
      expect(PhoneUtils.isSame('+91 98765 43210', '09876543210'), isTrue);
      expect(PhoneUtils.isSame('1234567890', '9876543210'), isFalse);
    });

    test('formatDisplay formats phone numbers cleanly', () {
      final formatted = PhoneUtils.formatDisplay('+919876543210');
      expect(formatted.isNotEmpty, isTrue);
      expect(formatted, '+91 98765 43210');
    });
  });
}
