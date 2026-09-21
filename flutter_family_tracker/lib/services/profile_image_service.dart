import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class ProfileImageService {
  static const String profileDirName = 'ProfileImages';
  static const String profileExt = '_profile_pic.jpg';

  static final ImagePicker _picker = ImagePicker();
  static Directory? _cachedProfileDir;
  static final Map<String, File?> _fileCache = {};

  // Normalize phone for safe filename
  static String _cleanPhone(String phone) {
    return phone.replaceAll(RegExp(r'[^0-9]'), '');
  }

  // Clear file cache for a member or all members
  static void invalidateCache([String? mobile]) {
    if (mobile != null) {
      _fileCache.remove(_cleanPhone(mobile));
    } else {
      _fileCache.clear();
      _cachedProfileDir = null;
    }
  }

  // Get local directory for profile images (cached)
  static Future<Directory?> _getProfileDirectory() async {
    if (kIsWeb) return null;
    if (_cachedProfileDir != null && _cachedProfileDir!.existsSync()) {
      return _cachedProfileDir;
    }
    try {
      Directory baseDir;
      try {
        final extDir = await getExternalStorageDirectory();
        baseDir = extDir ?? await getApplicationDocumentsDirectory();
      } catch (_) {
        baseDir = await getApplicationDocumentsDirectory();
      }

      final profileDir = Directory('${baseDir.path}/$profileDirName');
      if (!await profileDir.exists()) {
        await profileDir.create(recursive: true);
      }
      _cachedProfileDir = profileDir;
      return profileDir;
    } catch (_) {
      return null;
    }
  }

  // Get File object for a member's profile picture (with O(1) in-memory cache)
  static Future<File?> getProfileImageFile(String mobile) async {
    if (kIsWeb || mobile.isEmpty) return null;
    final clean = _cleanPhone(mobile);
    if (_fileCache.containsKey(clean)) {
      final cached = _fileCache[clean];
      if (cached != null && cached.existsSync()) {
        return cached;
      }
      _fileCache.remove(clean);
    }

    try {
      final dir = await _getProfileDirectory();
      if (dir == null) return null;

      final file = File('${dir.path}/$clean$profileExt');
      if (await file.exists()) {
        _fileCache[clean] = file;
        return file;
      }

      // Also check app docs directory fallback
      final docDir = await getApplicationDocumentsDirectory();
      final fallbackFile = File('${docDir.path}/$profileDirName/$clean$profileExt');
      if (await fallbackFile.exists()) {
        _fileCache[clean] = fallbackFile;
        return fallbackFile;
      }
    } catch (_) {}
    _fileCache[clean] = null;
    return null;
  }

  // Pick and Save Profile Picture (Camera or Gallery)
  static Future<File?> pickAndSaveProfileImage(
      String mobile, ImageSource source) async {
    if (kIsWeb || mobile.isEmpty) return null;
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (pickedFile == null) return null;

      final clean = _cleanPhone(mobile);
      final dir = await _getProfileDirectory();
      if (dir == null) return null;

      final targetPath = '${dir.path}/$clean$profileExt';

      final savedFile = await File(pickedFile.path).copy(targetPath);
      _fileCache[clean] = savedFile;
      debugPrint('[FamilyTracker] Profile image saved to: $targetPath');
      return savedFile;
    } catch (e) {
      debugPrint('[FamilyTracker] Error saving profile image: $e');
      return null;
    }
  }

  // Delete profile picture
  static Future<void> deleteProfileImage(String mobile) async {
    if (kIsWeb || mobile.isEmpty) return;
    try {
      final clean = _cleanPhone(mobile);
      final file = await getProfileImageFile(mobile);
      if (file != null && await file.exists()) {
        await file.delete();
      }
      _fileCache[clean] = null;
    } catch (_) {}
  }
}
