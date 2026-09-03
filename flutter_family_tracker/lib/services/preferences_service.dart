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

  static Future<void> clearSession() async {
    await _prefs?.clear();
  }
}
