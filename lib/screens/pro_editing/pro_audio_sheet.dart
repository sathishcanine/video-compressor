import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'pro_audio_session.dart';
import 'pro_audio_timeline_screen.dart';
import 'pro_canvas_session.dart';

/// Opens the full-screen audio workspace (multi-track timeline, music picker, pinch zoom).
Future<void> showProAudioSheet(
  BuildContext context, {
  required VideoPlayerController controller,
  required String videoPath,
  required List<Uint8List?> thumbnails,
  required Duration trimStart,
  required Duration trimEnd,
  ProCanvasSessionSettings? canvasSession,
  required ProAudioMixSession? initialSession,
  required Future<void> Function(String outputPath, ProAudioMixSession session) onCommit,
  required VoidCallback onForgetSession,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ProAudioTimelineScreen(
        controller: controller,
        videoPath: videoPath,
        thumbnails: thumbnails,
        trimStart: trimStart,
        trimEnd: trimEnd,
        canvasSession: canvasSession,
        initialSession: initialSession,
        onCommit: onCommit,
        onForgetSession: onForgetSession,
      ),
    ),
  );
}
