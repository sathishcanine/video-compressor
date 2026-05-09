/// Last successful audio mix in the current editor session.
///
/// [clipPathAfterMix] must equal the current clip file path for this session to
/// stay valid (reopen sheet with remembered track & levels). Undo, trim, or any
/// step that changes the file invalidates it.
class ProAudioMixSession {
  const ProAudioMixSession({
    required this.musicPath,
    required this.clipLinearGain,
    required this.musicLinearGain,
    required this.clipPathAfterMix,
    required this.mixIndex,
  });

  final String musicPath;
  final double clipLinearGain;
  final double musicLinearGain;
  final String clipPathAfterMix;
  /// 1 = first mix applied to this clip lineage at [clipPathAfterMix].
  final int mixIndex;

  ProAudioMixSession copyWith({
    String? musicPath,
    double? clipLinearGain,
    double? musicLinearGain,
    String? clipPathAfterMix,
    int? mixIndex,
  }) {
    return ProAudioMixSession(
      musicPath: musicPath ?? this.musicPath,
      clipLinearGain: clipLinearGain ?? this.clipLinearGain,
      musicLinearGain: musicLinearGain ?? this.musicLinearGain,
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
