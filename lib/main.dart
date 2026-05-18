import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'bootstrap/firebase_bootstrap.dart';
import 'screens/home_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrapFirebaseAndCrashlytics();
  await MobileAds.instance.initialize();
  runApp(const VidPressApp());
}

class VidPressApp extends StatelessWidget {
  const VidPressApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VidPress',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorObservers: firebaseReady
          ? <NavigatorObserver>[FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)]
          : const <NavigatorObserver>[],
      home: const HomeShell(),
    );
  }
}
