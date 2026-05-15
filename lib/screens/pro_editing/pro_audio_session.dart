/// One stacked music bed in the audio timeline (path + per-track linear gain).
class ProAudioMusicLayer {
  const ProAudioMusicLayer({
    required this.path,
    required this.linearGain,
  });

  final String path;
  /// Linear multiplier (1.0 = nominal), same range as FFmpeg volume in the mixer.
  final double linearGain;

  ProAudioMusicLayer copyWith({String? path, double? linearGain}) {
    return ProAudioMusicLayer(
      path: path ?? this.path,
      linearGain: linearGain ?? this.linearGain,
    );
  }
}

/// Last successful audio mix in the current editor session.
///
/// [clipPathAfterMix] must equal the current clip file path for this session to
/// stay valid (reopen with remembered layers). Undo, trim, or any step that
/// changes the file invalidates it.
class ProAudioMixSession {
  const ProAudioMixSession({
    required this.musicLayers,
    required this.clipLinearGain,
    required this.clipPathAfterMix,
    required this.mixIndex,
  });

  final List<ProAudioMusicLayer> musicLayers;
  final double clipLinearGain;
  final String clipPathAfterMix;
  /// 1 = first mix applied to this clip lineage at [clipPathAfterMix].
  final int mixIndex;

  ProAudioMixSession copyWith({
    List<ProAudioMusicLayer>? musicLayers,
    double? clipLinearGain,
    String? clipPathAfterMix,
    int? mixIndex,
  }) {
    return ProAudioMixSession(
      musicLayers: musicLayers ?? this.musicLayers,
      clipLinearGain: clipLinearGain ?? this.clipLinearGain,
      clipPathAfterMix: clipPathAfterMix ?? this.clipPathAfterMix,
      mixIndex: mixIndex ?? this.mixIndex,
    );
  }
}

/// Drop session when the timeline no longer shows the file this mix produced.
ProAudioMixSession? invalidateAudioSessionIfStale(ProAudioMixSession? session, String? currentClipPath) {
  if (session == null || currentClipPath == null) return null;
  if (currentClipPath != session.clipPathAfterMix) return null;
  return session;
}
