import 'package:flutter/foundation.dart';

/// Google sample AdMob **application** IDs (safe for development / debug).
/// Replace with your real App IDs before release.
abstract final class AdmobAppIds {
  static const String android = 'ca-app-pub-3940256099942544~3347511713';
  static const String ios = 'ca-app-pub-3940256099942544~1458002511';
}

/// Google sample **ad unit** IDs (always return test ads).
abstract final class AdmobTestAdUnits {
  static const String rewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const String rewardedIos = 'ca-app-pub-3940256099942544/1712485313';
  static const String nativeAndroid = 'ca-app-pub-3940256099942544/2247696110';
  static const String nativeIos = 'ca-app-pub-3940256099942544/3986624511';
}

abstract final class AdmobConfig {
  static String get rewardedAdUnitId =>
      defaultTargetPlatform == TargetPlatform.iOS ? AdmobTestAdUnits.rewardedIos : AdmobTestAdUnits.rewardedAndroid;

  static String get nativeAdUnitId =>
      defaultTargetPlatform == TargetPlatform.iOS ? AdmobTestAdUnits.nativeIos : AdmobTestAdUnits.nativeAndroid;
}
