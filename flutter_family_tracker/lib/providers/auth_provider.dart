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

    try {
      await _authService.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        resendToken: _resendToken,
        onCodeSent: (String verId, int? token) {
          _verificationId = verId;
          _resendToken = token;
          setLoading(false);
          onCodeSent();
        },
        onVerificationFailed: (FirebaseAuthException e) {
          setLoading(false);
          debugPrint('[FamilyTracker-Auth] Phone verification failed: code=${e.code}, message=${e.message}');
          String message = e.message ?? 'Phone verification failed';
          if (e.code == 'captcha-check-failed' || e.code == 'invalid-app-credential' || e.message?.toLowerCase().contains('recaptcha') == true) {
            message = 'Verification failed (invalid-app-credential). Please ensure SHA-256 fingerprint is added to Firebase Console (or Authorized Domains for Web).';
          } else if (e.code == 'app-not-authorized' || e.code == 'missing-client-identifier') {
            message = 'App not authorized. Please verify SHA-1 & SHA-256 certificates in Firebase Console.';
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
      );
      return true;
    } catch (e) {
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
