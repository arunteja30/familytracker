import 'dart:io';
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

  /// Show the OEM Auto-Start & Battery optimization modal manually (e.g. from Settings)
  static Future<void> show(BuildContext context, {bool isManualTrigger = false}) async {
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

  /// Automatically show on Dashboard on first launch if device is an aggressive OEM
  static Future<void> showIfNeeded(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return;

    final alreadyShown = PreferencesService.isAutostartGuidanceShown();
    if (alreadyShown) return;

    final oemInfo = await NativeService.getDeviceOemInfo();
    final isStrictOem = oemInfo?['isStrictOem'] as bool? ?? false;

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
      return 'Xiaomi / MIUI / HyperOS';
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
        'Step 1: Tap "1. Open Auto-Start Settings" and enable "Autostart" for FamilyTracker.',
        'Step 2: Tap "2. Battery: Select \'No Restrictions\'" and choose "No restrictions" so MIUI never freezes background tracking.',
      ];
    } else if (lower.contains('samsung')) {
      return [
        'Step 1: Tap "1. Open Auto-Start Settings" and add FamilyTracker to "Never sleeping apps".',
        'Step 2: Tap "2. Battery: Select \'No Restrictions\'" and set Battery to "Unrestricted".',
      ];
    } else if (lower.contains('oppo') || lower.contains('realme')) {
      return [
        'Step 1: Tap "1. Open Auto-Start Settings" and turn ON "Allow Auto-Launch".',
        'Step 2: Tap "2. Battery: Select \'No Restrictions\'" and allow background activity / turn off optimization.',
      ];
    } else if (lower.contains('vivo') || lower.contains('iqoo')) {
      return [
        'Step 1: Tap "1. Open Auto-Start Settings" and enable "Autostart" permission.',
        'Step 2: Tap "2. Battery: Select \'No Restrictions\'" and allow "High Background Power Consumption".',
      ];
    } else if (lower.contains('oneplus')) {
      return [
        'Step 1: Tap "1. Open Auto-Start Settings" and turn on "Auto-launch" for FamilyTracker.',
        'Step 2: Tap "2. Battery: Select \'No Restrictions\'" and select "Don\'t optimize" / "Unrestricted".',
      ];
    } else if (lower.contains('huawei') || lower.contains('honor')) {
      return [
        'Step 1: Tap "1. Open Auto-Start Settings", turn OFF "Manage automatically" and enable "Auto-launch" & "Run in background".',
        'Step 2: Tap "2. Battery: Select \'No Restrictions\'" and add FamilyTracker to protected apps.',
      ];
    }

    return [
      'Step 1: Tap "1. Open Auto-Start Settings" to enable Auto-Launch on startup if supported.',
      'Step 2: Tap "2. Battery: Select \'No Restrictions\'" to exempt FamilyTracker from battery optimization ("Unrestricted").',
    ];
  }

  Future<void> _handleOpenAutoStart() async {
    await NativeService.openOemAutoStartSettings();
  }

  Future<void> _handleOpenBatteryOptimization() async {
    await NativeService.openBatteryOptimizationSettings();
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
                    color: AppColors.textMuted.withValues(alpha: 0.3),
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
                      color: AppColors.primary.withValues(alpha: 0.12),
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
                'Background & Battery Setup',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),

              // Explanation
              const Text(
                'To ensure continuous family safety and instant SOS reception, your phone needs two quick permissions: Auto-Start on Boot and Battery "No Restrictions".',
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
                          '2-Step Setup for $brandTitle',
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
                              decoration: BoxDecoration(
                                color: i == 0 ? AppColors.primary : AppColors.accent,
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
                      if (i < instructions.length - 1) const SizedBox(height: 6),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons: Step 1 & Step 2
              // Step 1: Open Auto-Start
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _handleOpenAutoStart,
                  icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                  label: const Text('1. Open Auto-Start Settings'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Step 2: Open Battery Saver / No Restrictions
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _handleOpenBatteryOptimization,
                  icon: const Icon(Icons.battery_charging_full_rounded, size: 18),
                  label: const Text('2. Battery: Select "No Restrictions"'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 16),

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
                        side: const BorderSide(color: AppColors.cardBorder),
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
                      child: const Text('I\'ve Enabled Both'),
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
