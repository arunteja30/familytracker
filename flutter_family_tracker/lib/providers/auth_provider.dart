import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/preferences_service.dart';
import '../services/native_service.dart';
import '../models/registration_model.dart';

class AppAuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();

  bool _isLoading = false;
  String? _errorMessage;
  String? _verificationId;
  int? _resendToken;
  String? _currentPhoneNumber;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get verificationId => _verificationId;
  String? get currentPhoneNumber => _currentPhoneNumber;
  User? get currentUser => _authService.currentUser;

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setError(String? error) {
    _errorMessage = error;
    notifyListeners();
  }

  // Send OTP
  Future<bool> sendOtp({
    required String phoneNumber,
    required VoidCallback onCodeSent,
  }) async {
    setLoading(true);
    setError(null);
    _currentPhoneNumber = phoneNumber;

    Timer? failsafeTimer;
    failsafeTimer = Timer(const Duration(seconds: 90), () {
      if (_isLoading) {
        setLoading(false);
        setError('Verification request timed out. Please check your network connection and verify SHA fingerprints in Firebase Console.');
      }
    });

    try {
      debugPrint('[FamilyTracker-Auth] Requesting OTP verification for: $phoneNumber');
      await _authService.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        resendToken: _resendToken,
        onCodeSent: (String verId, int? token) {
          failsafeTimer?.cancel();
          debugPrint('[FamilyTracker-Auth] OTP code sent successfully. verificationId=$verId');
          _verificationId = verId;
          _resendToken = token;
          setLoading(false);
          onCodeSent();
        },
        onVerificationFailed: (FirebaseAuthException e) {
          failsafeTimer?.cancel();
          setLoading(false);
          debugPrint('[FamilyTracker-Auth] Phone verification failed: code=${e.code}, message=${e.message}');
          String message = e.message ?? 'Phone verification failed';
          if (e.code == 'captcha-check-failed' || e.code == 'invalid-app-credential' || e.message?.toLowerCase().contains('recaptcha') == true) {
            message = 'Verification failed (${e.code}): ${e.message ?? "Invalid app credential. Check SHA-256, Play Integrity API, or use a test phone number in Firebase Console."}';
          } else if (e.code == 'app-not-authorized' || e.code == 'missing-client-identifier') {
            message = 'App not authorized (${e.code}): Please verify SHA-1 & SHA-256 in Firebase Console.';
          } else if (e.code == 'too-many-requests') {
            message = 'Too many requests. Please wait a few moments before trying again.';
          } else if (e.code == 'quota-exceeded') {
            message = 'SMS quota exceeded for today. Please try again later or use a test phone number.';
          } else if (e.code == 'invalid-phone-number') {
            message = 'Invalid phone number format. Please ensure country code and 10-digit number are correct.';
          }
          setError(message);
        },
        onVerificationCompleted: (PhoneAuthCredential credential) async {
          failsafeTimer?.cancel();
          debugPrint('[FamilyTracker-Auth] Instant SMS verification completed');
          // Instant SMS verification on Android
          try {
            final userCredential = await _authService.signInWithCredential(credential);
            final user = userCredential.user;
            if (user != null) {
              final phone = user.phoneNumber ?? _currentPhoneNumber ?? '';
              await PreferencesService.saveUserPhone(phone);
              await PreferencesService.setLoggedIn(true);

              final regModel = RegistrationModel(
                phone: phone,
                name: user.displayName ?? 'User',
                uid: user.uid,
              );
              await _dbService.registerPhone(regModel);
              setLoading(false);
              notifyListeners();
            }
          } catch (e) {
            setLoading(false);
            setError(e.toString());
          }
        },
        onCodeAutoRetrievalTimeout: (String verId) {
          debugPrint('[FamilyTracker-Auth] SMS auto-retrieval window ended for verId=$verId. Manual OTP entry available.');
          _verificationId = verId;
        },
      );
      return true;
    } catch (e) {
      failsafeTimer.cancel();
      setLoading(false);
      setError(e.toString());
      return false;
    }
  }

  // Verify OTP & Sign In
  Future<bool> verifyOtp(String smsCode) async {
    if (_verificationId == null) {
      setError('Verification ID is missing. Please request a new code.');
      return false;
    }

    setLoading(true);
    setError(null);

    try {
      final userCredential = await _authService.signInWithOtp(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );

      final user = userCredential.user;
      if (user != null) {
        final phone = user.phoneNumber ?? _currentPhoneNumber ?? '';
        
        // Save phone to local storage
        await PreferencesService.saveUserPhone(phone);
        await PreferencesService.setLoggedIn(true);

        // Register in Database if not already present
        final regModel = RegistrationModel(
          phone: phone,
          name: user.displayName ?? 'User',
          uid: user.uid,
        );
        await _dbService.registerPhone(regModel);

        setLoading(false);
        return true;
      }

      setLoading(false);
      return false;
    } on FirebaseAuthException catch (e) {
      setLoading(false);
      setError(e.message ?? 'Invalid verification code');
      return false;
    } catch (e) {
      setLoading(false);
      setError(e.toString());
      return false;
    }
  }

  // Sign Out
  Future<void> signOut() async {
    await _authService.signOut();
    await NativeService.stopNativeStickyService();
    await NativeService.removeDeviceAdmin();
    await PreferencesService.clearSession();
    notifyListeners();
  }
}
