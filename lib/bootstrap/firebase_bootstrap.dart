import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Whether Firebase finished initialization (Remote Config / Crashlytics safe to use).
bool firebaseReady = false;

Future<void> bootstrapFirebaseAndCrashlytics() async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } on Object catch (e, st) {
    debugPrint('Firebase.initializeApp failed (run flutterfire configure): $e\n$st');
    return;
  }

  firebaseReady = true;

  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);

  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  try {
    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 20),
        minimumFetchInterval: kDebugMode ? Duration.zero : const Duration(hours: 1),
      ),
    );

    await rc.setDefaults(<String, Object>{
      'force_update_enabled': false,
      'min_supported_version_code': 1,
      'android_store_url': 'https://play.google.com/store/apps/details?id=com.vidcompressor.vidcompressor',
      'ios_store_url': '',
    });

    await rc.fetchAndActivate();
  } on Object catch (e, st) {
    debugPrint('Remote Config setup/fetch failed: $e\n$st');
  }
}
