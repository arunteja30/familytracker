import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/app_update_model.dart';
import '../ui/widgets/app_update_dialog.dart';
import 'database_service.dart';

class AppUpdateService {
  static final DatabaseService _dbService = DatabaseService();
  static bool _isUpdateDialogOpen = false;

  /// Check RTDB 'UpdateData' node once.
  /// If an update is available:
  /// - Prompts [AppUpdateDialog].
  /// - Returns `true` if update is MANDATORY (so caller halts navigation until updated).
  /// - Returns `false` if no update or optional.
  static Future<bool> checkAndPromptUpdate(BuildContext context) async {
    if (kIsWeb) return false;
    try {
      final update = await _dbService.getAppUpdate();
      if (update != null && update.shouldShowUpdate()) {
        if (context.mounted && !_isUpdateDialogOpen) {
          _isUpdateDialogOpen = true;
          await AppUpdateDialog.show(context, update);
          _isUpdateDialogOpen = false;
          return update.isMandatory;
        }
      }
    } catch (e) {
      debugPrint('[FamilyTracker] AppUpdate check error: $e');
    }
    return false;
  }

  /// Listen to RTDB 'UpdateData' real-time changes while the app is active
  static StreamSubscription<AppUpdateModel?> listenToAppUpdates(BuildContext context) {
    if (kIsWeb) return const Stream<AppUpdateModel?>.empty().listen((_) {});
    return _dbService.streamAppUpdate().listen((update) {
      if (update != null && update.shouldShowUpdate()) {
        if (context.mounted && !_isUpdateDialogOpen) {
          _isUpdateDialogOpen = true;
          AppUpdateDialog.show(context, update).then((_) {
            _isUpdateDialogOpen = false;
          });
        }
      }
    });
  }
}
