import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'native_service.dart';

class ContactsService {
  static final Map<String, String> _contactsCache = {};
  static bool _hasLoaded = false;

  // Load and cache all device contacts
  static Future<void> syncDeviceContacts() async {
    try {
      final status = await Permission.contacts.status;
      if (!status.isGranted) {
        final req = await Permission.contacts.request();
        if (!req.isGranted) return;
      }

      final Map<dynamic, dynamic>? contacts =
          await NativeService.getDeviceContacts();
      if (contacts != null) {
        _contactsCache.clear();
        contacts.forEach((key, value) {
          if (key != null && value != null) {
            _contactsCache[key.toString()] = value.toString();
          }
        });
        _hasLoaded = true;
        debugPrint(
            '[FamilyTracker] Synced ${_contactsCache.length} contact entries from phonebook');
      }
    } catch (e) {
      debugPrint('[FamilyTracker] Error syncing contacts: $e');
    }
  }

  // Get matching contact book name for a phone number
  static String getContactDisplayName(String phone, String defaultName) {
    if (phone.isEmpty) return defaultName;

    // Direct lookup
    if (_contactsCache.containsKey(phone)) {
      return _contactsCache[phone]!;
    }

    // Lookup by last 10 digits
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) {
      final last10 = digits.substring(digits.length - 10);
      if (_contactsCache.containsKey(last10)) {
        return _contactsCache[last10]!;
      }
    }

    return defaultName;
  }
}
