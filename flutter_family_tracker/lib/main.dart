import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'constants/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/family_provider.dart';
import 'services/preferences_service.dart';
import 'ui/screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Local Preferences
  await PreferencesService.init();

  // Initialize Firebase (Cross-Platform / Web / Mobile)
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
