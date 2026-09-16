import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../models/app_update_model.dart';

class AppUpdateDialog extends StatelessWidget {
  final AppUpdateModel updateModel;

  const AppUpdateDialog({
    super.key,
    required this.updateModel,
  });

  /// Show the update dialog popup
  static Future<void> show(BuildContext context, AppUpdateModel updateModel) async {
    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: !updateModel.isMandatory && updateModel.isDialogCancelable,
      builder: (_) => AppUpdateDialog(updateModel: updateModel),
    );
  }

  Future<void> _handleDownloadUrl(BuildContext context) async {
    final rawUrl = updateModel.url.trim();
    if (rawUrl.isEmpty) return;

    final uri = Uri.parse(rawUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('[FamilyTracker] Failed to launch update URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMandatory = updateModel.isMandatory;

    return PopScope(
      canPop: !isMandatory && updateModel.isDialogCancelable,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 10,
        backgroundColor: AppColors.bgSurface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Icon Badge
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  gradient: isMandatory
                      ? const LinearGradient(
                          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isMandatory ? Colors.red : AppColors.primary).withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(
                  isMandatory ? Icons.system_security_update_rounded : Icons.system_update_rounded,
                  size: 34,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 18),

              // Title
              Text(
                updateModel.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Version & Mandatory Badge Row
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  // Version Chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      'v${AppConstants.appVersionName} → v${updateModel.targetVersion}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),

                  // Mandatory Chip
                  if (isMandatory)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_clock_rounded, size: 13, color: Colors.red.shade700),
                          const SizedBox(width: 4),
                          Text(
                            'Required Update',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // Message Body
              Text(
                updateModel.message,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),

              // Release Notes (if any)
              if (updateModel.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bgApp,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.fiber_new_rounded, size: 16, color: AppColors.accent),
                          SizedBox(width: 6),
                          Text(
                            'What\'s New:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (final note in updateModel.releaseNotes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• ', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                              Expanded(
                                child: Text(
                                  note,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),

              // Action Buttons
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => _handleDownloadUrl(context),
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: Text(
                    isMandatory ? 'Update Now to Continue' : 'Download & Update',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isMandatory ? Colors.red.shade600 : AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),

              // Later Button (only if not mandatory)
              if (!isMandatory && updateModel.isDialogCancelable) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Maybe Later',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
