/// Canonical Phone Normalization Utility
///
/// Converts any raw input phone format (+919876543210, 09876543210, 9876543210)
/// into a standard uniform key for database indexing and matching.
class PhoneUtils {
  /// Extract standard 10-digit national number
  static String normalize(String rawPhone) {
    if (rawPhone.isEmpty) return '';
    final digits = rawPhone.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  /// Format phone with country code (e.g., +91 98765 43210)
  static String formatDisplay(String rawPhone, [String countryCode = '+91']) {
    final clean = normalize(rawPhone);
    if (clean.length == 10) {
      return '$countryCode ${clean.substring(0, 5)} ${clean.substring(5)}';
    }
    return rawPhone;
  }

  /// Check if two phone strings represent the same person
  static bool isSame(String p1, String p2) {
    if (p1.isEmpty || p2.isEmpty) return false;
    if (p1.trim() == p2.trim()) return true;
    final n1 = normalize(p1);
    final n2 = normalize(p2);
    return n1.isNotEmpty && n1 == n2;
  }
}
