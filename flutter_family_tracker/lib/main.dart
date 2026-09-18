import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'constants/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/family_provider.dart';
import 'services/preferences_service.dart';
import 'services/notification_service.dart';
import 'ui/screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Local Preferences & Notifications
  try {
    await PreferencesService.init();
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('Init error: $e');
  }

  // Initialize Firebase (Cross-Platform / Web / iOS / Android)
  try {
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
  } catch (e) {
    debugPrint('Firebase initialization notice: $e');
  }

  runApp(const FamilyTrackerApp());
}

class FamilyTrackerApp extends StatelessWidget {
  const FamilyTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppAuthProvider()),
        ChangeNotifierProvider(create: (_) => FamilyProvider()),
      ],
      child: MaterialApp(
        title: 'FamilyTracker',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const SplashScreen(),
      ),
    );
  }
}
