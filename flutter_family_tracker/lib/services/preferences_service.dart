import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

class PreferencesService {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<void> saveUserFamilyName(String familyName) async {
    await _prefs?.setString(AppConstants.prefUserFamilyName, familyName);
  }

  static String? getUserFamilyName() {
    return _prefs?.getString(AppConstants.prefUserFamilyName);
  }

  static Future<void> saveUserPhone(String phone) async {
    await _prefs?.setString(AppConstants.prefUserPhone, phone);
  }

  static String? getUserPhone() {
    return _prefs?.getString(AppConstants.prefUserPhone);
  }

  static Future<void> saveUserName(String name) async {
    await _prefs?.setString(AppConstants.prefUserName, name);
  }

  static String? getUserName() {
    return _prefs?.getString(AppConstants.prefUserName);
  }

  static Future<void> setLoggedIn(bool isLoggedIn) async {
    await _prefs?.setBool(AppConstants.prefIsLoggedIn, isLoggedIn);
  }

  static bool isLoggedIn() {
    return _prefs?.getBool(AppConstants.prefIsLoggedIn) ?? false;
  }

  static Future<void> setAutostartGuidanceShown(bool shown) async {
    await _prefs?.setBool(AppConstants.prefAutostartGuidanceShown, shown);
  }

  static bool isAutostartGuidanceShown() {
    return _prefs?.getBool(AppConstants.prefAutostartGuidanceShown) ?? false;
  }

  static Future<void> saveSecurityPin(String pin) async {
    await _prefs?.setString(AppConstants.prefSecurityPin, pin.trim());
  }

  static String? getSecurityPin() {
    return _prefs?.getString(AppConstants.prefSecurityPin);
  }

  static Future<void> setSecurityPinEnabled(bool enabled) async {
    await _prefs?.setBool(AppConstants.prefSecurityPinEnabled, enabled);
  }

  static bool isSecurityPinEnabled() {
    return _prefs?.getBool(AppConstants.prefSecurityPinEnabled) ?? false;
  }

  static int getFailedPinAttempts() {
    return _prefs?.getInt(AppConstants.prefFailedPinAttempts) ?? 0;
  }

  static Future<int> incrementFailedPinAttempts() async {
    final current = getFailedPinAttempts() + 1;
    await _prefs?.setInt(AppConstants.prefFailedPinAttempts, current);
    return current;
  }

  static Future<void> resetFailedPinAttempts() async {
    await _prefs?.setInt(AppConstants.prefFailedPinAttempts, 0);
  }

  static Future<void> clearSession() async {
    await _prefs?.clear();
  }
}
