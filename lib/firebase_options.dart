// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
//
// Android values match `android/app/google-services.json` (project vidpress-26e55).
// This JSON only registers Android — after you add an iOS app in Firebase, run
// `flutterfire configure` and replace the `ios` `appId` (and apiKey if shown).

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Add web in flutterfire configure if you need web.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Firebase is only wired for Android and iOS in this app.');
    }
  }

  /// From `android/app/google-services.json` (package com.vidcompressor.vidcompressor).
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD7MvEqE1hbaVwwKg4Tlc4NMfxLz7FmzsI',
    appId: '1:1069622834231:android:209e5d55399f9257abbbb2',
    messagingSenderId: '1069622834231',
    projectId: 'vidpress-26e55',
    storageBucket: 'vidpress-26e55.firebasestorage.app',
  );

  /// Same Firebase project as Android; `appId` must match an iOS app in Console.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD7MvEqE1hbaVwwKg4Tlc4NMfxLz7FmzsI',
    appId: '1:1069622834231:ios:0102030405060708090a0b0c',
    messagingSenderId: '1069622834231',
    projectId: 'vidpress-26e55',
    storageBucket: 'vidpress-26e55.firebasestorage.app',
    iosBundleId: 'com.vidcompressor.vidcompressor',
  );
}
