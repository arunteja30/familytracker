import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'native_service.dart';
import 'permission_service.dart';
import 'notification_service.dart';

class BackupResult {
  final bool success;
  final String? contactsFilePath;
  final String? callLogsFilePath;
  final String? smsFilePath;
  final String? filePath;
  final int contactsCount;
  final int callLogsCount;
  final int smsCount;
  final String? error;
  final DateTime timestamp;
  final int fileSizeBytes;

  BackupResult({
    required this.success,
    this.contactsFilePath,
    this.callLogsFilePath,
    this.smsFilePath,
    this.filePath,
    this.contactsCount = 0,
    this.callLogsCount = 0,
    this.smsCount = 0,
    this.error,
    DateTime? timestamp,
    this.fileSizeBytes = 0,
  }) : timestamp = timestamp ?? DateTime.now();

  int get totalCount => contactsCount + callLogsCount + smsCount;
  int get count => totalCount;

  String get formattedSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class BackupService {
  // Reactive Notifiers for non-blocking background execution
  static final ValueNotifier<bool> isBackupInProgress = ValueNotifier<bool>(false);
  static final ValueNotifier<BackupResult?> latestBackupNotifier = ValueNotifier<BackupResult?>(null);

  static Future<Directory> _getBackupDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${docsDir.path}/backups');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  /// Launch non-blocking background backup of Contacts, Call Logs, and SMS into separate files.
  /// Overwrites existing backup files so that storage holds only the single latest backup.
  static Future<BackupResult> runBackgroundBackup(BuildContext context) async {
    // 1. Request permissions explicitly on UI thread first
    final hasContacts = await PermissionService.requestContactsPermissionExplicitly(context);
    final hasSms = await PermissionService.requestSmsPermissionExplicitly(context);
    final hasCallLogs = await PermissionService.requestCallLogPermissionExplicitly(context);

    if (!hasContacts && !hasSms && !hasCallLogs) {
      return BackupResult(
        success: false,
        error: 'Required permissions (Contacts, SMS, Call Logs) were not granted.',
      );
    }

    // 2. Set active state so UI shows non-blocking progress immediately
    isBackupInProgress.value = true;

    try {
      // 3. Fetch data asynchronously
      Map<dynamic, dynamic>? contactsData;
      if (hasContacts) {
        contactsData = await NativeService.getDeviceContacts();
      }

      List<Map<String, dynamic>> callLogsData = [];
      if (hasCallLogs) {
        callLogsData = await NativeService.getDeviceCallLogs();
      }

      List<Map<String, dynamic>> smsData = [];
      if (hasSms) {
        smsData = await NativeService.getDeviceSms();
      }

      final contactsCount = contactsData?.length ?? 0;
      final callLogsCount = callLogsData.length;
      final smsCount = smsData.length;

      if (contactsCount == 0 && callLogsCount == 0 && smsCount == 0) {
        final failureResult = BackupResult(
          success: false,
          error: 'No contacts, call logs, or SMS messages found on device to backup.',
        );
        isBackupInProgress.value = false;
        return failureResult;
      }

      final backupDir = await _getBackupDirectory();
      final now = DateTime.now();
      final dateFormatted = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);

      // Clean up any legacy timestamped files in backups directory to keep only latest files
      try {
        final existingFiles = backupDir.listSync();
        for (final f in existingFiles) {
          if (f is File && f.path.endsWith('.txt')) {
            f.deleteSync();
          }
        }
      } catch (_) {}

      int totalBytes = 0;
      String? contactsFilePath;
      String? callLogsFilePath;
      String? smsFilePath;

      // ----------------------------------------------------------------------
      // FILE 1: SEPARATE CONTACTS BACKUP TXT (OVERWRITE)
      // ----------------------------------------------------------------------
      if (contactsData != null && contactsData.isNotEmpty) {
        final contactsFile = File('${backupDir.path}/contacts_backup.txt');
        final cBuf = StringBuffer();
        cBuf.writeln('================================================================');
        cBuf.writeln('FAMILYTRACKER CONTACTS BACKUP (LATEST)');
        cBuf.writeln('Backup Date: $dateFormatted');
        cBuf.writeln('Total Contacts: $contactsCount');
        cBuf.writeln('================================================================\n');

        int cIdx = 1;
        contactsData.forEach((phone, name) {
          cBuf.writeln('$cIdx. Name: $name');
          cBuf.writeln('   Phone: $phone');
          cBuf.writeln('----------------------------------------------------------------');
          cIdx++;
        });

        await contactsFile.writeAsString(cBuf.toString(), mode: FileMode.write, flush: true);
        contactsFilePath = contactsFile.path;
        totalBytes += await contactsFile.length();
      }

      // ----------------------------------------------------------------------
      // FILE 2: SEPARATE CALL LOGS BACKUP TXT (OVERWRITE)
      // ----------------------------------------------------------------------
      if (callLogsData.isNotEmpty) {
        final callLogsFile = File('${backupDir.path}/calllogs_backup.txt');
        final clBuf = StringBuffer();
        clBuf.writeln('================================================================');
        clBuf.writeln('FAMILYTRACKER CALL LOGS BACKUP (LATEST)');
        clBuf.writeln('Backup Date: $dateFormatted');
        clBuf.writeln('Total Call Logs: $callLogsCount');
        clBuf.writeln('================================================================\n');

        for (int i = 0; i < callLogsData.length; i++) {
          final log = callLogsData[i];
          final number = log['number'] ?? 'Unknown';
          final name = (log['name'] != null && log['name'].toString().isNotEmpty) ? ' (${log['name']})' : '';
          final type = log['type'] ?? 'UNKNOWN';
          final durSec = (log['duration'] as num?)?.toInt() ?? 0;
          final dateMs = (log['date'] as num?)?.toInt() ?? 0;
          final logDate = dateMs > 0 ? DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(dateMs)) : 'Unknown Date';

          clBuf.writeln('${i + 1}. [$type] $number$name');
          clBuf.writeln('   Date: $logDate | Duration: ${durSec}s');
          clBuf.writeln('----------------------------------------------------------------');
        }

        await callLogsFile.writeAsString(clBuf.toString(), mode: FileMode.write, flush: true);
        callLogsFilePath = callLogsFile.path;
        totalBytes += await callLogsFile.length();
      }

      // ----------------------------------------------------------------------
      // FILE 3: SEPARATE SMS BACKUP TXT (OVERWRITE)
      // ----------------------------------------------------------------------
      if (smsData.isNotEmpty) {
        final smsFile = File('${backupDir.path}/sms_backup.txt');
        final sBuf = StringBuffer();
        sBuf.writeln('================================================================');
        sBuf.writeln('FAMILYTRACKER SMS MESSAGES BACKUP (LATEST)');
        sBuf.writeln('Backup Date: $dateFormatted');
        sBuf.writeln('Total SMS Messages: $smsCount');
        sBuf.writeln('================================================================\n');

        for (int i = 0; i < smsData.length; i++) {
          final sms = smsData[i];
          final address = sms['address'] ?? 'Unknown';
          final type = sms['type'] ?? 'SMS';
          final body = (sms['body'] ?? '').toString().replaceAll('\n', ' ');
          final dateMs = (sms['date'] as num?)?.toInt() ?? 0;
          final smsDate = dateMs > 0 ? DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(dateMs)) : 'Unknown Date';
          final isRead = sms['isRead'] == true ? 'READ' : 'UNREAD';

          sBuf.writeln('${i + 1}. [$type] $address');
          sBuf.writeln('   Date: $smsDate | Status: $isRead');
          sBuf.writeln('   Message: $body');
          sBuf.writeln('----------------------------------------------------------------');
        }

        await smsFile.writeAsString(sBuf.toString(), mode: FileMode.write, flush: true);
        smsFilePath = smsFile.path;
        totalBytes += await smsFile.length();
      }

      // ----------------------------------------------------------------------
      // METADATA JSON INDEX (OVERWRITE)
      // ----------------------------------------------------------------------
      final latestJsonFile = File('${backupDir.path}/latest_backup.json');
      await latestJsonFile.writeAsString(jsonEncode({
        'timestamp': now.millisecondsSinceEpoch,
        'contactsCount': contactsCount,
        'callLogsCount': callLogsCount,
        'smsCount': smsCount,
        'contactsFilePath': contactsFilePath,
        'callLogsFilePath': callLogsFilePath,
        'smsFilePath': smsFilePath,
        'filePath': contactsFilePath ?? callLogsFilePath ?? smsFilePath,
        'fileSizeBytes': totalBytes,
      }), mode: FileMode.write, flush: true);

      final result = BackupResult(
        success: true,
        contactsFilePath: contactsFilePath,
        callLogsFilePath: callLogsFilePath,
        smsFilePath: smsFilePath,
        filePath: contactsFilePath ?? callLogsFilePath ?? smsFilePath,
        contactsCount: contactsCount,
        callLogsCount: callLogsCount,
        smsCount: smsCount,
        timestamp: now,
        fileSizeBytes: totalBytes,
      );

      // Dispatch local completion notification
      await NotificationService.showBackupCompleteNotification(
        contactsCount: contactsCount,
        callLogsCount: callLogsCount,
        smsCount: smsCount,
        formattedSize: result.formattedSize,
      );

      latestBackupNotifier.value = result;
      isBackupInProgress.value = false;
      return result;
    } catch (e) {
      final errResult = BackupResult(
        success: false,
        error: 'Failed to generate backup: $e',
      );
      isBackupInProgress.value = false;
      return errResult;
    }
  }

  // Get info about the most recent backup
  static Future<BackupResult?> getLatestBackupInfo() async {
    try {
      final backupDir = await _getBackupDirectory();
      final latestJsonFile = File('${backupDir.path}/latest_backup.json');
      if (await latestJsonFile.exists()) {
        final content = await latestJsonFile.readAsString();
        final data = jsonDecode(content);
        final timestamp = DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int);
        final contactsCount = (data['contactsCount'] as int?) ?? (data['count'] as int?) ?? 0;
        final callLogsCount = (data['callLogsCount'] as int?) ?? 0;
        final smsCount = (data['smsCount'] as int?) ?? 0;
        final contactsFilePath = data['contactsFilePath'] as String?;
        final callLogsFilePath = data['callLogsFilePath'] as String?;
        final smsFilePath = data['smsFilePath'] as String?;
        final filePath = data['filePath'] as String?;
        final fileSizeBytes = (data['fileSizeBytes'] as int?) ?? await latestJsonFile.length();

        final result = BackupResult(
          success: true,
          contactsFilePath: contactsFilePath,
          callLogsFilePath: callLogsFilePath,
          smsFilePath: smsFilePath,
          filePath: filePath ?? contactsFilePath ?? callLogsFilePath ?? smsFilePath ?? latestJsonFile.path,
          contactsCount: contactsCount,
          callLogsCount: callLogsCount,
          smsCount: smsCount,
          timestamp: timestamp,
          fileSizeBytes: fileSizeBytes,
        );
        latestBackupNotifier.value = result;
        return result;
      } else {
        // Fallback legacy latest_contacts.json
        final legacyJson = File('${backupDir.path}/latest_contacts.json');
        if (await legacyJson.exists()) {
          final content = await legacyJson.readAsString();
          final data = jsonDecode(content);
          final timestamp = DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int);
          final count = (data['count'] as int?) ?? 0;
          final fileSize = await legacyJson.length();
          final result = BackupResult(
            success: true,
            contactsFilePath: legacyJson.path,
            filePath: legacyJson.path,
            contactsCount: count,
            timestamp: timestamp,
            fileSizeBytes: fileSize,
          );
          latestBackupNotifier.value = result;
          return result;
        }
      }
    } catch (_) {}
    return null;
  }
}
