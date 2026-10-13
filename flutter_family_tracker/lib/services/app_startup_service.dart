import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'notification_service.dart';
import 'preferences_service.dart';

class AppStartupService {
  static Future<void>? _initialization;

  static Future<void> initialize() =>
      _initialization ??= _initializeServices();

  static Future<void> _initializeServices() async {
    await Future.wait([
      _runStep('Preferences', PreferencesService.init, const Duration(seconds: 3)),
      _runStep('Notifications', NotificationService.initialize, const Duration(seconds: 4)),
      _runStep('Firebase', _initializeFirebase, const Duration(seconds: 8)),
    ]);
  }

  static Future<void> _runStep(
    String name,
    Future<void> Function() initialize,
    Duration timeout,
  ) async {
    try {
      await initialize().timeout(timeout);
    } catch (error) {
      debugPrint('[Startup] $name initialization did not finish: $error');
    }
  }

  static Future<void> _initializeFirebase() async {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyCqdmb42a0bZ6wtrfad_wmGe0SeseMx5KQ',
          appId: '1:133174163927:web:31e7d1eab0f92262',
          messagingSenderId: '133174163927',
          projectId: 'familytracker-3231f',
          databaseURL: 'https://familytracker-3231f.firebaseio.com',
          storageBucket: 'familytracker-3231f.appspot.com',
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyCqdmb42a0bZ6wtrfad_wmGe0SeseMx5KQ',
          appId: '1:133174163927:ios:31e7d1eab0f92262',
          messagingSenderId: '133174163927',
          projectId: 'familytracker-3231f',
          databaseURL: 'https://familytracker-3231f.firebaseio.com',
          storageBucket: 'familytracker-3231f.appspot.com',
          iosClientId: '133174163927-9gvi45kfmbnbqv8hg5ut652kvcuosifk.apps.googleusercontent.com',
          iosBundleId: 'com.mat.familytrack',
        ),
      );
    } else {
      await Firebase.initializeApp();
    }
  }
}