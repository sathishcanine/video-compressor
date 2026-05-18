import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bootstrap/firebase_bootstrap.dart';

/// Remote Config keys (match Firebase console).
abstract final class RemoteConfigKeys {
  static const forceUpdateEnabled = 'force_update_enabled';
  static const minSupportedVersionCode = 'min_supported_version_code';
  static const androidStoreUrl = 'android_store_url';
  static const iosStoreUrl = 'ios_store_url';
}

Future<void> maybeShowForceUpdateDialog(BuildContext context) async {
  if (!firebaseReady || !context.mounted) return;

  final rc = FirebaseRemoteConfig.instance;
  final force = rc.getBool(RemoteConfigKeys.forceUpdateEnabled);
  if (!force) return;

  final minSupported = rc.getInt(RemoteConfigKeys.minSupportedVersionCode);
  final info = await PackageInfo.fromPlatform();
  final current = int.tryParse(info.buildNumber) ?? 0;

  if (current >= minSupported) return;
  if (!context.mounted) return;

  final storeUri = _storeUri(rc);
  if (storeUri == null) {
    debugPrint('Force update: no store URL available for this platform.');
    return;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Update required'),
          content: Text(
            'This version is no longer supported (build $current; minimum $minSupported). '
            'Install the latest VidPress to continue.',
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                final launched = await launchUrl(storeUri, mode: LaunchMode.externalApplication);
                if (!launched && ctx.mounted) {
                  ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
                    const SnackBar(content: Text('Could not open the store. Try again from the store app.')),
                  );
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      );
    },
  );
}

Uri? _storeUri(FirebaseRemoteConfig rc) {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      final s = rc.getString(RemoteConfigKeys.androidStoreUrl).trim();
      if (s.isEmpty) {
        return Uri.parse('https://play.google.com/store/apps/details?id=com.vidcompressor.vidcompressor');
      }
      return Uri.tryParse(s);
    case TargetPlatform.iOS:
      final s = rc.getString(RemoteConfigKeys.iosStoreUrl).trim();
      if (s.isNotEmpty) return Uri.tryParse(s);
      return Uri.parse('https://apps.apple.com/search?term=VidPress');
    default:
      return null;
  }
}
