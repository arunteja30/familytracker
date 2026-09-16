import '../constants/app_constants.dart';

class AppUpdateModel {
  final String url;
  final String title;
  final String message;
  final String targetVersion;
  final int targetVersionCode;
  final bool isMandatory;
  final bool isDialogCancelable;
  final String? notificationMessage;
  final List<String> releaseNotes;

  const AppUpdateModel({
    required this.url,
    required this.title,
    required this.message,
    required this.targetVersion,
    this.targetVersionCode = 0,
    required this.isMandatory,
    this.isDialogCancelable = true,
    this.notificationMessage,
    this.releaseNotes = const [],
  });

  factory AppUpdateModel.fromMap(Map<dynamic, dynamic> map) {
    // 1. URL extraction (supports 'url', 'download_url', 'downloadUrl', 'link', 'apkUrl')
    final rawUrl = (map['url'] ??
            map['download_url'] ??
            map['downloadUrl'] ??
            map['link'] ??
            map['apkUrl'] ??
            '')
        .toString()
        .trim();

    // 2. Title extraction
    final rawTitle = (map['title'] ??
            map['updateTitle'] ??
            map['dialogTitle'] ??
            'Update Available')
        .toString()
        .trim();

    // 3. Message extraction
    final rawMessage = (map['message'] ??
            map['updateMessage'] ??
            map['description'] ??
            'A new and improved version of FamilyTracker is available. Please update now to ensure continuous live location and emergency SOS tracking.')
        .toString()
        .trim();

    // 4. Version extraction (supports float, int, or String e.g. "1.1", "1.0.1", 2)
    final rawVersion = (map['version'] ??
            map['latest_version'] ??
            map['versionName'] ??
            map['app_version'] ??
            '1.0.0')
        .toString()
        .trim();

    // 5. Version Code
    int rawVersionCode = 0;
    if (map['versionCode'] != null) {
      rawVersionCode = int.tryParse(map['versionCode'].toString()) ?? 0;
    } else if (map['version_code'] != null) {
      rawVersionCode = int.tryParse(map['version_code'].toString()) ?? 0;
    }

    // 6. Mandatory / Force Update extraction
    bool mandatoryFlag = false;
    final rawMandatory = map['mandatory'] ?? map['force_update'] ?? map['forceUpdate'] ?? map['isMandatory'];
    if (rawMandatory != null) {
      final str = rawMandatory.toString().trim().toUpperCase();
      if (str == 'YES' || str == 'TRUE' || str == '1' || rawMandatory == true) {
        mandatoryFlag = true;
      }
    }

    // 7. Dialog Cancelable
    bool cancelable = true;
    if (map['isDialogCancelable'] != null) {
      final cVal = map['isDialogCancelable'];
      if (cVal is bool) {
        cancelable = cVal;
      } else if (cVal.toString().toLowerCase() == 'false') {
        cancelable = false;
      }
    }
    if (mandatoryFlag) {
      cancelable = false;
    }

    // 8. Notification Message
    final notifMsg = map['notificationMessage']?.toString();

    // 9. Release Notes
    List<String> notes = [];
    if (map['releaseNotes'] is List) {
      notes = (map['releaseNotes'] as List).map((e) => e.toString()).toList();
    } else if (map['release_notes'] is List) {
      notes = (map['release_notes'] as List).map((e) => e.toString()).toList();
    } else if (map['notes'] is String) {
      notes = (map['notes'] as String)
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return AppUpdateModel(
      url: rawUrl,
      title: rawTitle.isNotEmpty ? rawTitle : 'Update Available',
      message: rawMessage.isNotEmpty ? rawMessage : 'A new version of FamilyTracker is available.',
      targetVersion: rawVersion,
      targetVersionCode: rawVersionCode,
      isMandatory: mandatoryFlag || !cancelable,
      isDialogCancelable: cancelable,
      notificationMessage: notifMsg,
      releaseNotes: notes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'title': title,
      'message': message,
      'version': targetVersion,
      'versionCode': targetVersionCode,
      'mandatory': isMandatory ? 'YES' : 'NO',
      'isDialogCancelable': isDialogCancelable,
      if (notificationMessage != null) 'notificationMessage': notificationMessage,
      if (releaseNotes.isNotEmpty) 'releaseNotes': releaseNotes,
    };
  }

  /// Determines whether an update should be presented to the user
  bool shouldShowUpdate({
    String currentVersionName = AppConstants.appVersionName,
    int currentVersionCode = AppConstants.appVersionCode,
  }) {
    if (url.isEmpty) return false;

    // 1. If remote specifies a versionCode higher than current versionCode
    if (targetVersionCode > 0 && targetVersionCode > currentVersionCode) {
      return true;
    }

    // 2. Semantic / Float version comparison
    return _isRemoteVersionHigher(currentVersionName, targetVersion);
  }

  static bool _isRemoteVersionHigher(String current, String remote) {
    if (remote.isEmpty || current.isEmpty) return false;
    if (current.trim() == remote.trim()) return false;

    // Try float comparison first (e.g. 1.0 vs 1.1)
    final currentFloat = double.tryParse(current);
    final remoteFloat = double.tryParse(remote);
    if (currentFloat != null && remoteFloat != null) {
      return remoteFloat > currentFloat;
    }

    // Try semantic dot comparison (e.g. 1.0.0 vs 1.0.1)
    final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final remoteParts = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final maxLen = currentParts.length > remoteParts.length ? currentParts.length : remoteParts.length;

    for (int i = 0; i < maxLen; i++) {
      final curr = i < currentParts.length ? currentParts[i] : 0;
      final rem = i < remoteParts.length ? remoteParts[i] : 0;
      if (rem > curr) return true;
      if (rem < curr) return false;
    }

    return false;
  }
}
