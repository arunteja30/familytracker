import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class ProfileImageService {
  static const String profileDirName = 'ProfileImages';
  static const String profileExt = '_profile_pic.jpg';

  static final ImagePicker _picker = ImagePicker();

  // Normalize phone for safe filename
  static String _cleanPhone(String phone) {
    return phone.replaceAll(RegExp(r'[^0-9]'), '');
  }

  // Get local directory for profile images
  static Future<Directory> _getProfileDirectory() async {
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
    return profileDir;
  }

  // Get File object for a member's profile picture
  static Future<File?> getProfileImageFile(String mobile) async {
    if (mobile.isEmpty) return null;
    try {
      final clean = _cleanPhone(mobile);
      final dir = await _getProfileDirectory();
      final file = File('${dir.path}/$clean$profileExt');
      if (await file.exists()) {
        return file;
      }

      // Also check app docs directory fallback
      final docDir = await getApplicationDocumentsDirectory();
      final fallbackFile = File('${docDir.path}/$profileDirName/$clean$profileExt');
      if (await fallbackFile.exists()) {
        return fallbackFile;
      }
    } catch (_) {}
    return null;
  }

  // Pick and Save Profile Picture (Camera or Gallery)
  static Future<File?> pickAndSaveProfileImage(
      String mobile, ImageSource source) async {
    if (mobile.isEmpty) return null;
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
      final targetPath = '${dir.path}/$clean$profileExt';

      final savedFile = await File(pickedFile.path).copy(targetPath);
      debugPrint('[FamilyTracker] Profile image saved to: $targetPath');
      return savedFile;
    } catch (e) {
      debugPrint('[FamilyTracker] Error saving profile image: $e');
      return null;
    }
  }

  // Delete profile picture
  static Future<void> deleteProfileImage(String mobile) async {
    try {
      final file = await getProfileImageFile(mobile);
      if (file != null && await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
