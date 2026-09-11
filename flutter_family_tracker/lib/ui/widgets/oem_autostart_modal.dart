import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../services/native_service.dart';
import '../../services/preferences_service.dart';

class OemAutoStartModal extends StatefulWidget {
  final Map<String, dynamic>? oemInfo;
  final bool isManualTrigger;

  const OemAutoStartModal({
    super.key,
    this.oemInfo,
    this.isManualTrigger = false,
  });

  static Future<void> show(BuildContext context, {bool isManualTrigger = true}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final oemInfo = await NativeService.getDeviceOemInfo();

    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OemAutoStartModal(
        oemInfo: oemInfo,
        isManualTrigger: isManualTrigger,
      ),
    );
  }

  static Future<void> showIfNeeded(BuildContext context) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final alreadyShown = PreferencesService.isAutostartGuidanceShown();
    if (alreadyShown) return;

    final oemInfo = await NativeService.getDeviceOemInfo();
    final isStrictOem = oemInfo?['isStrictOem'] as bool? ?? false;

    // Prompt automatically on devices with aggressive background killers
    if (isStrictOem && context.mounted) {
      await show(context, isManualTrigger: false);
    }
  }

  @override
  State<OemAutoStartModal> createState() => _OemAutoStartModalState();
}

class _OemAutoStartModalState extends State<OemAutoStartModal> {
  late String _manufacturer;
  late String _brand;
  late String _model;

  @override
  void initState() {
    super.initState();
    _manufacturer = (widget.oemInfo?['manufacturer'] as String? ?? '').trim();
    _brand = (widget.oemInfo?['brand'] as String? ?? '').trim();
    _model = (widget.oemInfo?['model'] as String? ?? '').trim();
  }

  String get _detectedBrandName {
    final lower = ('$_manufacturer $_brand').toLowerCase();
    if (lower.contains('xiaomi') || lower.contains('redmi') || lower.contains('poco')) {
      return 'Xiaomi / MIUI';
    } else if (lower.contains('samsung')) {
      return 'Samsung (One UI)';
    } else if (lower.contains('oppo')) {
      return 'OPPO (ColorOS)';
    } else if (lower.contains('realme')) {
      return 'Realme (Realme UI)';
    } else if (lower.contains('vivo') || lower.contains('iqoo')) {
      return 'Vivo / iQOO';
    } else if (lower.contains('oneplus')) {
      return 'OnePlus (OxygenOS)';
    } else if (lower.contains('huawei') || lower.contains('honor')) {
      return 'Huawei / Honor';
    } else if (lower.contains('asus')) {
      return 'ASUS (ZenUI)';
    }
    return _manufacturer.isNotEmpty ? _manufacturer.toUpperCase() : 'Android Device';
  }

  IconData get _brandIcon {
    final lower = ('$_manufacturer $_brand').toLowerCase();
    if (lower.contains('samsung')) return Icons.phone_android_rounded;
    if (lower.contains('xiaomi') || lower.contains('redmi') || lower.contains('poco')) return Icons.bolt_rounded;
    if (lower.contains('oppo') || lower.contains('realme')) return Icons.speed_rounded;
    if (lower.contains('vivo') || lower.contains('iqoo')) return Icons.flash_on_rounded;
    if (lower.contains('oneplus')) return Icons.offline_bolt_rounded;
    return Icons.settings_power_rounded;
  }

  List<String> get _instructions {
    final lower = ('$_manufacturer $_brand').toLowerCase();

    if (lower.contains('xiaomi') || lower.contains('redmi') || lower.contains('poco')) {
      return [
        'Tap "Open Settings" below to launch Autostart management.',
        'Locate and enable "Autostart" for FamilyTracker.',
        'Go to Battery Saver options and select "No restrictions".',
      ];
    } else if (lower.contains('samsung')) {
      return [
        'Tap "Open Settings" below to open Battery settings.',
        'Navigate to "Background usage limits" > "Never sleeping apps".',
        'Tap the "+" icon and add FamilyTracker to the whitelist.',
      ];
    } else if (lower.contains('oppo') || lower.contains('realme')) {
      return [
        'Tap "Open Settings" below to open Startup App list.',
        'Enable "Allow Auto-Launch" for FamilyTracker.',
        'Enable "Allow background activity" in App Battery usage.',
      ];
    } else if (lower.contains('vivo') || lower.contains('iqoo')) {
      return [
        'Tap "Open Settings" below to access Permission Manager.',
        'Turn on "Autostart" permission for FamilyTracker.',
        'Under "High Background Power Consumption", allow continuous operation.',
      ];
    } else if (lower.contains('oneplus')) {
      return [
        'Tap "Open Settings" below to access Battery settings.',
        'Under "Battery Optimization", choose "Don\'t optimize".',
        'Enable "Allow background activity" for uninterrupted safety tracking.',
      ];
    } else if (lower.contains('huawei') || lower.contains('honor')) {
      return [
        'Tap "Open Settings" below to access App Launch settings.',
        'Turn OFF "Manage automatically" for FamilyTracker.',
        'Enable "Auto-launch", "Secondary launch", and "Run in background".',
      ];
    }

    return [
      'Tap "Open Settings" below to open App Info.',
      'Select "Battery" or "Battery usage".',
      'Change the battery setting from Optimized to "Unrestricted".',
    ];
  }

  Future<void> _handleOpenSettings() async {
    await NativeService.openOemAutoStartSettings();
  }

  Future<void> _handleDismiss(bool markAsDone) async {
    if (markAsDone) {
      await PreferencesService.setAutostartGuidanceShown(true);
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brandTitle = _detectedBrandName;
    final instructions = _instructions;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Detected OEM Badge
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_brandIcon, size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          brandTitle,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (_model.isNotEmpty)
                    Text(
                      _model,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // Title
              const Text(
                'Enable Auto-Start on Boot',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),

              // Explanation
              const Text(
                'To ensure continuous family safety, your device must allow FamilyTracker to automatically restart after reboot and stay active without being killed by battery saving policies.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),

              // Instructions Card
              Container(
                decoration: BoxDecoration(
                  color: AppColors.bgApp,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.checklist_rounded,
                          size: 20,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Quick Setup for $brandTitle',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (int i = 0; i < instructions.length; i++) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                instructions[i],
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (i < instructions.length - 1) const SizedBox(height: 4),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Primary Action Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _handleOpenSettings,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text('Open $brandTitle Settings'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Done / Close Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _handleDismiss(false),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        side: BorderSide(color: AppColors.cardBorder),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Remind Later',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _handleDismiss(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      child: const Text('I\'ve Enabled It'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
