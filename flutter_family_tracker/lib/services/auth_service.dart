import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  ConfirmationResult? _webConfirmationResult;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Send Verification Code to Phone Number
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(String verificationId, int? resendToken) onCodeSent,
    required Function(FirebaseAuthException e) onVerificationFailed,
    required Function(PhoneAuthCredential credential) onVerificationCompleted,
    int? resendToken,
  }) async {
    // On Flutter Web, use signInWithPhoneNumber to properly initialize RecaptchaVerifier
    if (kIsWeb) {
      try {
        _webConfirmationResult = await _auth.signInWithPhoneNumber(phoneNumber);
        onCodeSent(_webConfirmationResult!.verificationId, resendToken);
      } on FirebaseAuthException catch (e) {
        onVerificationFailed(e);
      } catch (e) {
        onVerificationFailed(FirebaseAuthException(
          code: 'web-phone-auth-error',
          message: e.toString(),
        ));
      }
      return;
    }

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: onVerificationCompleted,
      verificationFailed: onVerificationFailed,
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: (String verificationId) {},
      forceResendingToken: resendToken,
    );
  }

  // Sign In with SMS OTP
  Future<UserCredential> signInWithOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    if (kIsWeb && _webConfirmationResult != null) {
      return await _webConfirmationResult!.confirm(smsCode);
    }
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return await _auth.signInWithCredential(credential);
  }

  // Sign In with PhoneAuthCredential (Auto-Verification)
  Future<UserCredential> signInWithCredential(PhoneAuthCredential credential) async {
    return await _auth.signInWithCredential(credential);
  }

  // Sign Out
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
