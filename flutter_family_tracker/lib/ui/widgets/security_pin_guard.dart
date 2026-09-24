import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../../constants/app_colors.dart';
import '../../models/alert_item_model.dart';
import '../../services/database_service.dart';
import '../../services/native_service.dart';
import '../../services/preferences_service.dart';

enum PinGuardMode {
  verify,
  setup,
  change,
}

/// Ultra-Modern Security PIN & Intruder Guard UI
///
/// Provides in-app lockscreen protection with failed attempt tracking.
/// When 2 wrong attempts are entered, it triggers full intruder protocol:
/// dual-camera selfie capture, siren alert, email dispatch, and RTDB alert logging.
class SecurityPinGuard extends StatefulWidget {
  final PinGuardMode mode;
  final VoidCallback? onUnlocked;
  final VoidCallback? onCancelled;
  final String title;
  final String subtitle;

  const SecurityPinGuard({
    super.key,
    this.mode = PinGuardMode.verify,
    this.onUnlocked,
    this.onCancelled,
    this.title = 'Security PIN Guard',
    this.subtitle = 'Enter 4-digit PIN to authenticate',
  });

  static Future<bool> show({
    required BuildContext context,
    PinGuardMode mode = PinGuardMode.verify,
    String? title,
    String? subtitle,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: mode != PinGuardMode.verify,
      enableDrag: mode != PinGuardMode.verify,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SecurityPinGuard(
        mode: mode,
        title: title ?? (mode == PinGuardMode.setup ? 'Create Security PIN' : 'Security PIN Guard'),
        subtitle: subtitle ?? (mode == PinGuardMode.setup ? 'Set a 4-digit master PIN for anti-theft defense' : 'Enter 4-digit PIN to continue'),
        onUnlocked: () => Navigator.of(ctx).pop(true),
        onCancelled: () => Navigator.of(ctx).pop(false),
      ),
    );
    return result ?? false;
  }

  @override
  State<SecurityPinGuard> createState() => _SecurityPinGuardState();
}

class _SecurityPinGuardState extends State<SecurityPinGuard>
    with SingleTickerProviderStateMixin {
  String _enteredPin = '';
  String _firstEntryPin = '';
  bool _isConfirming = false;
  String _errorMessage = '';
  bool _isIntruderAlertTriggered = false;
  static const int _maxAllowedAttempts = 2;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 12)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onDigitPressed(String digit) {
    if (_enteredPin.length >= 4) return;
    HapticFeedback.lightImpact();

    setState(() {
      _enteredPin += digit;
      _errorMessage = '';
    });

    if (_enteredPin.length == 4) {
      _processCompletePin();
    }
  }

  void _onBackspacePressed() {
    if (_enteredPin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _errorMessage = '';
    });
  }

  Future<void> _processCompletePin() async {
    if (widget.mode == PinGuardMode.verify) {
      final savedPin = PreferencesService.getSecurityPin() ?? '1234';
      if (_enteredPin == savedPin) {
        // Successful unlock
        await PreferencesService.resetFailedPinAttempts();
        HapticFeedback.mediumImpact();
        if (mounted) {
          widget.onUnlocked?.call();
        }
      } else {
        // Failed attempt!
        await _handleFailedAttempt();
      }
    } else if (widget.mode == PinGuardMode.setup || widget.mode == PinGuardMode.change) {
      if (!_isConfirming) {
        setState(() {
          _firstEntryPin = _enteredPin;
          _enteredPin = '';
          _isConfirming = true;
        });
      } else {
        if (_enteredPin == _firstEntryPin) {
          await PreferencesService.saveSecurityPin(_enteredPin);
          await PreferencesService.setSecurityPinEnabled(true);
          await PreferencesService.resetFailedPinAttempts();
          HapticFeedback.mediumImpact();
          if (mounted) {
            widget.onUnlocked?.call();
          }
        } else {
          _triggerShake();
          setState(() {
            _errorMessage = 'PINs did not match. Please start over.';
            _enteredPin = '';
            _firstEntryPin = '';
            _isConfirming = false;
          });
        }
      }
    }
  }

  Future<void> _handleFailedAttempt() async {
    _triggerShake();
    HapticFeedback.heavyImpact();

    final newAttempts = await PreferencesService.incrementFailedPinAttempts();
    setState(() {
      _enteredPin = '';
    });

    if (newAttempts >= _maxAllowedAttempts) {
      setState(() {
        _isIntruderAlertTriggered = true;
        _errorMessage = '🚨 2 WRONG ATTEMPTS DETECTED!\nIntruder Defense Triggered.';
      });
      await _dispatchIntruderProtocol();
    } else {
      final remaining = _maxAllowedAttempts - newAttempts;
      setState(() {
        _errorMessage = 'Incorrect PIN! $remaining attempt(s) remaining before alarm & photo capture.';
      });
    }
  }

  void _triggerShake() {
    _shakeController.forward(from: 0.0);
  }

  Future<void> _dispatchIntruderProtocol() async {
    debugPrint('[SecurityPinGuard] 🚨 Triggering full intruder protocol for iOS & Android parity...');

    // 1. Fetch anti-theft config
    final config = await NativeService.getAntiTheftConfig();
    final alertEmail = config?['alertEmail'] as String? ?? '';
    final siren = config?['siren'] as bool? ?? true;
    final dualCam = config?['dualCam'] as bool? ?? true;

    // 2. Sound siren and capture photo(s) headlessly via Native MethodChannel
    await NativeService.testIntruderAlarm(
      alertEmail: alertEmail,
      playSiren: siren,
      dualCam: dualCam,
    );

    // 3. Log security alert to Firebase RTDB feed
    try {
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 4),
        );
      } catch (_) {}

      final latStr = position != null ? '${position.latitude}, ${position.longitude}' : 'Unavailable';
      final currentUserPhone = PreferencesService.getUserPhone() ?? 'Device Owner';

      DatabaseService().logAlert(
        AlertItemModel(
          id: '',
          familyName: '',
          type: AlertType.intruder,
          title: '🚨 INTRUDER PIN BREACH DETECTED',
          body: '2 incorrect security PIN attempts entered on $currentUserPhone. Secret intruder selfies captured.',
          memberMobile: currentUserPhone,
          memberName: 'Anti-Theft Guard',
          extraInfo: 'Location: $latStr',
        ),
      );
    } catch (e) {
      debugPrint('[SecurityPinGuard] Failed to log alert to RTDB: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, max(bottomPadding, 16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Security Icon / Glowing Badge
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: _isIntruderAlertTriggered
                  ? const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFB91C1C)])
                  : AppColors.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (_isIntruderAlertTriggered ? AppColors.danger : AppColors.primary).withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              _isIntruderAlertTriggered ? Icons.warning_rounded : Icons.shield_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),

          // Title & Subtitle
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isConfirming
                ? 'Confirm your 4-digit PIN'
                : (_isIntruderAlertTriggered
                    ? 'Intruder sirens & selfie capture activated'
                    : widget.subtitle),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: _isIntruderAlertTriggered ? AppColors.danger : AppColors.textSecondary,
              fontWeight: _isIntruderAlertTriggered ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 20),

          // Error / Alert banner
          if (_errorMessage.isNotEmpty)
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (ctx, child) => Transform.translate(
                offset: Offset(sin(_shakeAnimation.value * pi) * 6, 0),
                child: child,
              ),
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: AppColors.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // PIN Dots Indicator
          AnimatedBuilder(
            animation: _shakeAnimation,
            builder: (ctx, child) => Transform.translate(
              offset: Offset(sin(_shakeAnimation.value * pi) * 8, 0),
              child: child,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                final isFilled = index < _enteredPin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFilled
                        ? (_isIntruderAlertTriggered ? AppColors.danger : AppColors.primary)
                        : Colors.transparent,
                    border: Border.all(
                      color: isFilled
                          ? (_isIntruderAlertTriggered ? AppColors.danger : AppColors.primary)
                          : AppColors.cardBorder,
                      width: 2,
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 24),

          // Numeric Keypad
          _buildNumericKeypad(),

          const SizedBox(height: 12),

          // Cancel or dismiss button
          if (widget.onCancelled != null && widget.mode != PinGuardMode.verify)
            TextButton(
              onPressed: widget.onCancelled,
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNumericKeypad() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'delete'],
    ];

    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((key) {
              if (key.isEmpty) {
                return const SizedBox(width: 72, height: 72);
              }
              if (key == 'delete') {
                return SizedBox(
                  width: 72,
                  height: 72,
                  child: IconButton(
                    icon: const Icon(Icons.backspace_outlined, size: 24, color: AppColors.textSecondary),
                    onPressed: _onBackspacePressed,
                  ),
                );
              }
              return _buildKeypadButton(key);
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKeypadButton(String digit) {
    const lettersMap = {
      '1': '',
      '2': 'ABC',
      '3': 'DEF',
      '4': 'GHI',
      '5': 'JKL',
      '6': 'MNO',
      '7': 'PQRS',
      '8': 'TUV',
      '9': 'WXYZ',
      '0': '+',
    };

    final letters = lettersMap[digit] ?? '';

    return InkWell(
      onTap: () => _onDigitPressed(digit),
      borderRadius: BorderRadius.circular(36),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.bgSurfaceElevated,
          border: Border.all(color: AppColors.cardBorder.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              digit,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            if (letters.isNotEmpty)
              Text(
                letters,
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: AppColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
