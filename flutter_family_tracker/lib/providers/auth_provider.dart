import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/preferences_service.dart';
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
          setError(e.message ?? 'Phone verification failed');
        },
        onVerificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-resolution
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
    await PreferencesService.clearSession();
    notifyListeners();
  }
}
