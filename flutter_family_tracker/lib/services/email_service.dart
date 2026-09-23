import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'database_service.dart';
import 'native_service.dart';

class EmailService {
  static const String _smtpHost = 'smtp.gmail.com';
  static const int _smtpPort = 465;

  /// Send test or real Intruder Alert Email with optional photos and coordinates
  static Future<Map<String, dynamic>> sendIntruderAlertEmail({
    required String recipientEmail,
    String? senderEmail,
    String? senderPassword,
    List<String> photoPaths = const [],
    double? latitude,
    double? longitude,
  }) async {
    final credentials = await _resolveCredentials(senderEmail, senderPassword);
    final sender = credentials['sender'] ?? '';
    final pass = credentials['pass'] ?? '';

    if (pass.isEmpty) {
      return {
        'success': false,
        'error': '16-digit Google App Password is not configured in Settings or Firebase RTDB (/EmailConfig).',
      };
    }

    final finalSender = sender.isNotEmpty ? sender : recipientEmail;
    final now = DateFormat('dd MMM yyyy, hh:mm:ss a').format(DateTime.now());
    final oemInfo = await NativeService.getDeviceOemInfo();
    final deviceName = _formatDeviceName(oemInfo);

    final mapLinkHtml = (latitude != null && longitude != null && latitude != 0.0 && longitude != 0.0)
        ? '''
<div style="margin: 16px 0; padding: 12px; background: #f0fdf4; border: 1px solid #86efac; border-radius: 8px;">
    <p style="margin: 0 0 8px 0; font-weight: bold; color: #166534;">📍 Intruder Location Recorded:</p>
    <p style="margin: 0 0 8px 0; color: #374151;">Coordinates: <code>$latitude, $longitude</code></p>
    <a href="https://maps.google.com/?q=$latitude,$longitude" style="display: inline-block; padding: 8px 16px; background: #2563eb; color: #ffffff; text-decoration: none; border-radius: 6px; font-weight: bold;">View On Google Maps</a>
</div>
'''
        : '<p style="color: #6b7280; font-style: italic;">Location: Unable to fetch GPS fix during lock screen event.</p>';

    final validFiles = photoPaths.map((p) => File(p)).where((f) => f.existsSync() && f.lengthSync() > 0).toList();
    final photosCountText = validFiles.isNotEmpty
        ? '${validFiles.length} secret photo(s) captured and attached to this email.'
        : 'Test security dispatch without active camera captures.';

    final htmlBody = '''
<!DOCTYPE html>
<html>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #f8fafc; padding: 20px; color: #1e293b;">
    <div style="max-width: 600px; margin: 0 auto; background: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); border: 1px solid #e2e8f0;">
        <div style="background: linear-gradient(135deg, #ef4444, #b91c1c); color: white; padding: 24px; text-align: center;">
            <h1 style="margin: 0; font-size: 22px; font-weight: bold;">🚨 Intruder Warning Alert</h1>
            <p style="margin: 8px 0 0 0; opacity: 0.9; font-size: 14px;">FamilyTracker Anti-Theft Protection</p>
        </div>
        <div style="padding: 24px;">
            <p style="font-size: 15px; line-height: 1.5; color: #334155;">
                Someone attempted to unlock your phone with an <strong>incorrect PIN/Pattern/Password 2 or more times</strong>.
            </p>
            
            <table style="width: 100%; border-collapse: collapse; margin: 16px 0; font-size: 14px;">
                <tr style="border-bottom: 1px solid #f1f5f9;">
                    <td style="padding: 8px 0; color: #64748b;">📱 Device Name:</td>
                    <td style="padding: 8px 0; font-weight: bold; text-align: right; color: #1e293b;">$deviceName</td>
                </tr>
                <tr style="border-bottom: 1px solid #f1f5f9;">
                    <td style="padding: 8px 0; color: #64748b;">🕒 Timestamp:</td>
                    <td style="padding: 8px 0; font-weight: bold; text-align: right;">$now</td>
                </tr>
                <tr>
                    <td style="padding: 8px 0; color: #64748b;">📷 Photos Captured:</td>
                    <td style="padding: 8px 0; font-weight: bold; text-align: right; color: #ef4444;">${validFiles.length} Attached</td>
                </tr>
            </table>

            $mapLinkHtml

            <p style="font-size: 13px; color: #64748b; margin-top: 20px;">
                $photosCountText
            </p>
            
            <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 24px 0;">
            <p style="font-size: 12px; color: #94a3b8; text-align: center; margin: 0;">
                Protected by FamilyTracker Anti-Theft Protection. This is an automated security dispatch.
            </p>
        </div>
    </div>
</body>
</html>
''';

    return await _dispatchSmtp(
      senderEmail: finalSender,
      senderPassword: pass,
      recipientEmail: recipientEmail,
      subject: '🚨 INTRUDER ALERT: Failed Lock Screen Attempts on $deviceName',
      htmlBody: htmlBody,
      attachmentFiles: validFiles,
    );
  }

  /// Send device data backup files (Contacts, Call Logs, SMS) as attachments
  static Future<Map<String, dynamic>> sendBackupFilesEmail({
    required String recipientEmail,
    required List<String> filePaths,
    String? senderEmail,
    String? senderPassword,
  }) async {
    final credentials = await _resolveCredentials(senderEmail, senderPassword);
    final sender = credentials['sender'] ?? '';
    final pass = credentials['pass'] ?? '';

    if (pass.isEmpty) {
      return {
        'success': false,
        'error': '16-digit Google App Password is not configured in Settings or Firebase RTDB (/EmailConfig).',
      };
    }

    final validFiles = filePaths.map((p) => File(p)).where((f) => f.existsSync() && f.lengthSync() > 0).toList();
    if (validFiles.isEmpty) {
      return {
        'success': false,
        'error': 'No backup files found on device to send. Please create a backup first.',
      };
    }

    final finalSender = sender.isNotEmpty ? sender : recipientEmail;
    final now = DateFormat('dd MMM yyyy, hh:mm:ss a').format(DateTime.now());
    final oemInfo = await NativeService.getDeviceOemInfo();
    final deviceName = _formatDeviceName(oemInfo);

    final totalSize = validFiles.fold<int>(0, (sum, f) => sum + f.lengthSync());
    final formattedSize = totalSize < 1024 * 1024
        ? '${(totalSize / 1024).toStringAsFixed(1)} KB'
        : '${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB';

    final fileRowsHtml = validFiles.map((f) {
      final name = f.path.split(Platform.isWindows ? '\\' : '/').last;
      final sizeKb = '${(f.lengthSync() / 1024.0).toStringAsFixed(1)} KB';
      return '''
<tr style="border-bottom: 1px solid #f1f5f9;">
    <td style="padding: 8px 0; color: #334155; font-weight: 500;">📄 $name</td>
    <td style="padding: 8px 0; font-weight: bold; text-align: right; color: #64748b;">$sizeKb</td>
</tr>
''';
    }).join();

    final htmlBody = '''
<!DOCTYPE html>
<html>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #f8fafc; padding: 20px; color: #1e293b;">
    <div style="max-width: 600px; margin: 0 auto; background: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1); border: 1px solid #e2e8f0;">
        <div style="background: linear-gradient(135deg, #10b981, #059669); color: white; padding: 24px; text-align: center;">
            <h1 style="margin: 0; font-size: 22px; font-weight: bold;">📦 Device Data Backup</h1>
            <p style="margin: 8px 0 0 0; opacity: 0.9; font-size: 14px;">FamilyTracker Safe Device Backup</p>
        </div>
        <div style="padding: 24px;">
            <p style="font-size: 15px; line-height: 1.5; color: #334155;">
                A new device data backup has been generated and is attached to this email.
            </p>
            
            <table style="width: 100%; border-collapse: collapse; margin: 16px 0; font-size: 14px;">
                <tr style="border-bottom: 1px solid #f1f5f9;">
                    <td style="padding: 8px 0; color: #64748b;">📱 Device Name:</td>
                    <td style="padding: 8px 0; font-weight: bold; text-align: right; color: #1e293b;">$deviceName</td>
                </tr>
                <tr style="border-bottom: 1px solid #f1f5f9;">
                    <td style="padding: 8px 0; color: #64748b;">🕒 Backup Timestamp:</td>
                    <td style="padding: 8px 0; font-weight: bold; text-align: right;">$now</td>
                </tr>
                <tr style="border-bottom: 1px solid #f1f5f9;">
                    <td style="padding: 8px 0; color: #64748b;">📦 Total Size:</td>
                    <td style="padding: 8px 0; font-weight: bold; text-align: right; color: #10b981;">$formattedSize</td>
                </tr>
            </table>

            <h4 style="margin: 16px 0 8px 0; color: #1e293b;">Attached Backup Files:</h4>
            <table style="width: 100%; border-collapse: collapse; margin-bottom: 16px; font-size: 14px;">
                $fileRowsHtml
            </table>

            <div style="margin: 16px 0; padding: 12px; background: #f0fdf4; border: 1px solid #86efac; border-radius: 8px;">
                <p style="margin: 0; color: #166534; font-size: 13px;">
                    ✅ Backup files are attached as plain text (.txt). You can view them on any device.
                </p>
            </div>
            
            <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 24px 0;">
            <p style="font-size: 12px; color: #94a3b8; text-align: center; margin: 0;">
                FamilyTracker Security & Data Backup System.
            </p>
        </div>
    </div>
</body>
</html>
''';

    return await _dispatchSmtp(
      senderEmail: finalSender,
      senderPassword: pass,
      recipientEmail: recipientEmail,
      subject: '📦 Device Data Backup ($deviceName) - FamilyTracker',
      htmlBody: htmlBody,
      attachmentFiles: validFiles,
    );
  }

  /// Low-level cross-platform SMTP dispatcher over TLS (SSL port 465)
  static Future<Map<String, dynamic>> _dispatchSmtp({
    required String senderEmail,
    required String senderPassword,
    required String recipientEmail,
    required String subject,
    required String htmlBody,
    List<File> attachmentFiles = const [],
  }) async {
    SecureSocket? socket;
    try {
      debugPrint('[EmailService] Connecting to $_smtpHost:$_smtpPort over SSL...');
      socket = await SecureSocket.connect(
        _smtpHost,
        _smtpPort,
        timeout: const Duration(seconds: 25),
        onBadCertificate: (_) => true,
      );

      final buffer = StringBuffer();
      Future<String> readResponse() async {
        buffer.clear();
        await for (final data in socket!) {
          final text = utf8.decode(data, allowMalformed: true);
          buffer.write(text);
          if (text.contains('\n')) break;
        }
        final resp = buffer.toString().trim();
        debugPrint('[EmailService] SMTP << $resp');
        return resp;
      }

      void sendCommand(String cmd, {bool redact = false}) {
        if (!redact) {
          debugPrint('[EmailService] SMTP >> $cmd');
        } else {
          debugPrint('[EmailService] SMTP >> [REDACTED]');
        }
        socket!.write('$cmd\r\n');
      }

      // 1. Greet (220)
      final greet = await readResponse();
      if (!greet.startsWith('220')) {
        throw Exception('SMTP server rejected initial connection: $greet');
      }

      // 2. EHLO
      sendCommand('EHLO localhost');
      final ehloResp = await readResponse();
      if (!ehloResp.startsWith('250')) {
        throw Exception('EHLO failed: $ehloResp');
      }

      // 3. AUTH LOGIN
      sendCommand('AUTH LOGIN');
      final authResp = await readResponse();
      if (!authResp.startsWith('334')) {
        throw Exception('AUTH LOGIN rejected: $authResp');
      }

      // 4. Send base64 username
      sendCommand(base64Encode(utf8.encode(senderEmail)));
      final userResp = await readResponse();
      if (!userResp.startsWith('334')) {
        throw Exception('Username rejected: $userResp');
      }

      // 5. Send base64 app password (strip any internal spaces)
      final cleanPass = senderPassword.replaceAll(' ', '');
      sendCommand(base64Encode(utf8.encode(cleanPass)), redact: true);
      final passResp = await readResponse();
      if (!passResp.startsWith('235')) {
        throw Exception('Authentication failed (Check 16-digit Google App Password): $passResp');
      }

      // 6. MAIL FROM
      sendCommand('MAIL FROM:<$senderEmail>');
      final mailResp = await readResponse();
      if (!mailResp.startsWith('250')) {
        throw Exception('MAIL FROM rejected: $mailResp');
      }

      // 7. RCPT TO
      sendCommand('RCPT TO:<$recipientEmail>');
      final rcptResp = await readResponse();
      if (!rcptResp.startsWith('250')) {
        throw Exception('RCPT TO rejected for $recipientEmail: $rcptResp');
      }

      // 8. DATA
      sendCommand('DATA');
      final dataResp = await readResponse();
      if (!dataResp.startsWith('354')) {
        throw Exception('DATA command rejected: $dataResp');
      }

      // 9. Write MIME message
      final boundary = 'FamilyTracker_${DateTime.now().millisecondsSinceEpoch}';
      socket.write('From: FamilyTracker <$senderEmail>\r\n');
      socket.write('To: <$recipientEmail>\r\n');
      socket.write('Subject: $subject\r\n');
      socket.write('MIME-Version: 1.0\r\n');
      socket.write('Content-Type: multipart/mixed; boundary="$boundary"\r\n\r\n');

      // HTML part
      socket.write('--$boundary\r\n');
      socket.write('Content-Type: text/html; charset=UTF-8\r\n');
      socket.write('Content-Transfer-Encoding: base64\r\n\r\n');
      socket.write('${base64Encode(utf8.encode(htmlBody))}\r\n\r\n');

      // Attachments
      for (final file in attachmentFiles) {
        if (!file.existsSync()) continue;
        final fileName = file.path.split(Platform.isWindows ? '\\' : '/').last;
        final bytes = await file.readAsBytes();
        final base64Content = base64Encode(bytes);

        socket.write('--$boundary\r\n');
        final isImage = fileName.toLowerCase().endsWith('.jpg') || fileName.toLowerCase().endsWith('.jpeg');
        final mimeType = isImage ? 'image/jpeg' : 'text/plain';
        socket.write('Content-Type: $mimeType; name="$fileName"\r\n');
        socket.write('Content-Disposition: attachment; filename="$fileName"\r\n');
        socket.write('Content-Transfer-Encoding: base64\r\n\r\n');

        // Write in 76-character wrapped lines for RFC 2045 compliance
        for (int i = 0; i < base64Content.length; i += 76) {
          final end = (i + 76 < base64Content.length) ? i + 76 : base64Content.length;
          socket.write('${base64Content.substring(i, end)}\r\n');
        }
        socket.write('\r\n');
      }

      socket.write('--$boundary--\r\n\r\n');
      socket.write('.\r\n');

      final sendResp = await readResponse();
      if (!sendResp.startsWith('250')) {
        throw Exception('Failed to transmit message: $sendResp');
      }

      // 10. QUIT
      sendCommand('QUIT');
      await socket.flush();
      await socket.close();
      debugPrint('[EmailService] ✅ Email sent successfully to $recipientEmail');

      return {'success': true, 'message': 'Email dispatched successfully via SMTP.'};
    } catch (e) {
      debugPrint('[EmailService] ❌ SMTP Error: $e');
      return {'success': false, 'error': e.toString()};
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  /// Resolve sender email and password from parameters, native layer, or Firebase RTDB
  static Future<Map<String, String>> _resolveCredentials(String? senderEmail, String? senderPassword) async {
    String sender = senderEmail?.trim() ?? '';
    String pass = senderPassword?.trim() ?? '';

    // 1. Check native layer / local settings
    if (pass.isEmpty) {
      final nativeConfig = await NativeService.getAntiTheftConfig();
      if (nativeConfig != null) {
        if (sender.isEmpty) {
          sender = (nativeConfig['senderEmail'] ?? '').toString().trim();
        }
        pass = (nativeConfig['senderPassword'] ?? '').toString().trim();
      }
    }

    // 2. Query Firebase RTDB /EmailConfig
    if (pass.isEmpty) {
      final rtdbConfig = await DatabaseService().getEmailConfig();
      if (rtdbConfig != null) {
        if (sender.isEmpty) {
          sender = (rtdbConfig['senderEmail'] ?? rtdbConfig['email'] ?? '').toString().trim();
        }
        pass = (rtdbConfig['appPassword'] ?? rtdbConfig['password'] ?? rtdbConfig['pass'] ?? '').toString().trim();
      }
    }

    return {'sender': sender, 'pass': pass};
  }

  static String _formatDeviceName(Map<String, dynamic>? oem) {
    if (oem == null) return Platform.operatingSystem;
    final manufacturer = (oem['manufacturer'] ?? '').toString();
    final model = (oem['model'] ?? '').toString();
    if (model.isNotEmpty) {
      if (manufacturer.isNotEmpty && !model.toLowerCase().contains(manufacturer.toLowerCase())) {
        return '$manufacturer $model';
      }
      return model;
    }
    return manufacturer.isNotEmpty ? manufacturer : Platform.operatingSystem;
  }
}
