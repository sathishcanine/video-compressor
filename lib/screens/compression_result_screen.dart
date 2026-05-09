import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../ads/admob_config.dart';
import '../models/compression_preset.dart';
import '../theme/app_colors.dart';

class CompressionResultScreen extends StatefulWidget {
  const CompressionResultScreen({
    super.key,
    required this.preset,
    required this.isCustom,
    required this.customSubtitle,
    required this.originalVideoPath,
    required this.videoPath,
    required this.savingsPercent,
    required this.originalMb,
    required this.compressedMb,
    required this.onSaveToGallery,
  });

  final CompressionPreset preset;
  final bool isCustom;
  final String customSubtitle;
  /// Source file on disk (before compression) for side-by-side preview.
  final String originalVideoPath;
  /// Compressed output path.
  final String videoPath;
  final int savingsPercent;
  final double originalMb;
  final double compressedMb;
  final Future<void> Function() onSaveToGallery;

  @override
  State<CompressionResultScreen> createState() => _CompressionResultScreenState();
}

class _CompressionResultScreenState extends State<CompressionResultScreen> {
  static const double _previewRowHeight = 176;

  VideoPlayerController? _originalPreview;
  VideoPlayerController? _compressedPreview;
  NativeAd? _nativeAd;
  bool _nativeLoaded = false;

  RewardedAd? _rewardedAd;
  /// User completed the rewarded ad; primary button switches to save.
  bool _gallerySaveUnlocked = false;
  /// Loading ad or ad is being displayed (first step).
  bool _adFlowBusy = false;
  /// Saving file to gallery (second step).
  bool _savingToGallery = false;

  @override
  void initState() {
    super.initState();
    _originalPreview = VideoPlayerController.file(File(widget.originalVideoPath));
    _compressedPreview = VideoPlayerController.file(File(widget.videoPath));
    Future.wait([
      _originalPreview!.initialize(),
      _compressedPreview!.initialize(),
    ]).then((_) async {
      if (!mounted) return;
      final o = _originalPreview;
      final p = _compressedPreview;
      if (o == null || p == null) return;
      await o.setVolume(0);
      await o.pause();
      await p.setVolume(0);
      await p.pause();
      setState(() {});
    });

    _nativeAd = NativeAd(
      adUnitId: AdmobConfig.nativeAdUnitId,
      listener: NativeAdListener(
        onAdLoaded: (_) => setState(() => _nativeLoaded = true),
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) {
            setState(() {
              _nativeAd = null;
              _nativeLoaded = false;
            });
          }
        },
      ),
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: AppColors.background,
        cornerRadius: 12,
      ),
    )..load();

    _preloadRewarded();
  }

  void _preloadRewarded() {
    RewardedAd.load(
      adUnitId: AdmobConfig.rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _rewardedAd = ad);
        },
        onAdFailedToLoad: (_) {
          if (mounted) setState(() => _rewardedAd = null);
        },
      ),
    );
  }

  Future<RewardedAd?> _loadRewardedFresh() async {
    final completer = Completer<RewardedAd?>();
    RewardedAd.load(
      adUnitId: AdmobConfig.rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: completer.complete,
        onAdFailedToLoad: (_) => completer.complete(null),
      ),
    );
    return completer.future;
  }

  void _unlockGallerySaveBecauseAdUnavailable(String message) {
    if (!mounted) return;
    setState(() => _gallerySaveUnlocked = true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showRewardedAdToUnlockSave() async {
    if (_adFlowBusy || _gallerySaveUnlocked) return;
    setState(() => _adFlowBusy = true);

    try {
      var ad = _rewardedAd;
      if (ad != null) {
        setState(() => _rewardedAd = null);
      } else {
        ad = await _loadRewardedFresh();
      }

      if (!mounted) return;

      if (ad == null) {
        _unlockGallerySaveBecauseAdUnavailable(
          'No ad available from AdMob right now. You can still save to your gallery.',
        );
        _preloadRewarded();
        return;
      }

      var earned = false;

      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          if (!mounted) return;
          if (!earned) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Watch the full ad to unlock saving to your gallery.')),
            );
          }
          _preloadRewarded();
        },
        onAdFailedToShowFullScreenContent: (ad, err) {
          ad.dispose();
          if (!mounted) return;
          _unlockGallerySaveBecauseAdUnavailable(
            'Ad could not be shown. You can still save to your gallery.',
          );
          _preloadRewarded();
        },
      );

      try {
        await ad.show(
          onUserEarnedReward: (ad, reward) {
            earned = true;
            if (mounted) {
              setState(() => _gallerySaveUnlocked = true);
            }
          },
        );
      } catch (_) {
        if (!mounted) return;
        _unlockGallerySaveBecauseAdUnavailable(
          'Ad could not be played. You can still save to your gallery.',
        );
        _preloadRewarded();
      }
    } finally {
      if (mounted) setState(() => _adFlowBusy = false);
    }
  }

  Future<void> _saveToGallery() async {
    if (_savingToGallery || !_gallerySaveUnlocked) return;
    setState(() => _savingToGallery = true);
    try {
      await widget.onSaveToGallery();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to gallery')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingToGallery = false);
    }
  }

  Future<void> _onPrimaryGalleryButtonPressed() async {
    if (_gallerySaveUnlocked) {
      await _saveToGallery();
    } else {
      await _showRewardedAdToUnlockSave();
    }
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    _originalPreview?.dispose();
    _compressedPreview?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final savedMb = (widget.originalMb - widget.compressedMb).clamp(0, double.infinity);
    final subtitle = widget.isCustom ? widget.customSubtitle : widget.preset.name;
    final originalC = _originalPreview;
    final compressedC = _compressedPreview;
    final previewsReady = originalC != null &&
        compressedC != null &&
        originalC.value.isInitialized &&
        compressedC.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: !previewsReady
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.paddingOf(context).bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Compression Done!',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$subtitle preset',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_nativeAd != null && _nativeLoaded)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          height: 280,
                          child: AdWidget(ad: _nativeAd!),
                        ),
                      ),
                    if (_nativeAd != null && _nativeLoaded) const SizedBox(height: 16),
                    _sectionTitle(context, 'Preview & Analysis'),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _previewComparePane(
                            context,
                            label: 'Before',
                            mbLabel: 'Original file',
                            mb: widget.originalMb,
                            controller: originalC,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Icon(
                            Icons.compare_arrows_rounded,
                            color: AppColors.textSecondary.withValues(alpha: 0.45),
                            size: 26,
                          ),
                        ),
                        Expanded(
                          child: _previewComparePane(
                            context,
                            label: 'After',
                            mbLabel: 'Compressed output',
                            mb: widget.compressedMb,
                            controller: compressedC,
                            savingsPercent: widget.savingsPercent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'File size',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.originalMb > 0) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                height: 12,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ColoredBox(
                                      color: AppColors.textSecondary.withValues(alpha: 0.12),
                                    ),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: (widget.compressedMb / widget.originalMb).clamp(0.0, 1.0),
                                        heightFactor: 1,
                                        child: const ColoredBox(color: AppColors.success),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Compressed file is ${((widget.compressedMb / widget.originalMb) * 100).clamp(0, 999).toStringAsFixed(0)}% of the original size.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Original',
                                      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
                                    ),
                                    Text(
                                      '${widget.originalMb.toStringAsFixed(1)} MB',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.arrow_forward_rounded, color: AppColors.success.withValues(alpha: 0.8)),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Compressed',
                                      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
                                    ),
                                    Text(
                                      '${widget.compressedMb.toStringAsFixed(1)} MB',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.success,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 86,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Saved',
                                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    Text(
                                      '${savedMb.toStringAsFixed(1)} MB',
                                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.primary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: (_adFlowBusy || _savingToGallery) ? null : _onPrimaryGalleryButtonPressed,
                      icon: _savingToGallery || (_adFlowBusy && !_gallerySaveUnlocked)
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(
                              _gallerySaveUnlocked ? Icons.download_rounded : Icons.play_circle_outline_rounded,
                              color: Colors.white,
                            ),
                      label: Text(
                        _gallerySaveUnlocked
                            ? (_savingToGallery ? 'Saving…' : 'Save to Gallery')
                            : (_adFlowBusy ? 'Loading ad…' : 'Watch ad to Save to Gallery'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.35)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () async {
                              await Share.shareXFiles(
                                [XFile(widget.videoPath)],
                                text: 'Compressed with VidPress',
                              );
                            },
                            icon: const Icon(Icons.ios_share_rounded, size: 18),
                            label: const Text('Share', style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _roundMiniAction(icon: Icons.chat_bubble_outline, color: const Color(0xFF25D366), bg: const Color(0xFFDFF7E4)),
                        _roundMiniAction(icon: Icons.help_outline_rounded, color: const Color(0xFF2563EB), bg: const Color(0xFFE0ECFF)),
                        _roundMiniAction(icon: Icons.more_horiz_rounded, color: AppColors.textSecondary, bg: AppColors.background),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Row(
      children: [
        Icon(Icons.analytics_outlined, size: 22, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }

  Widget _previewComparePane(
    BuildContext context, {
    required String label,
    required String mbLabel,
    required double mb,
    required VideoPlayerController controller,
    int? savingsPercent,
  }) {
    final sz = controller.value.size;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          mbLabel,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          '${mb.toStringAsFixed(1)} MB',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _previewRowHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.06),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (sz.width > 0 && sz.height > 0)
                    FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: sz.width,
                        height: sz.height,
                        child: VideoPlayer(controller),
                      ),
                    )
                  else
                    const Center(child: Icon(Icons.videocam_rounded, color: AppColors.textSecondary)),
                  Center(
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                  if (savingsPercent != null)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.trending_down_rounded, color: Colors.white, size: 12),
                            const SizedBox(width: 3),
                            Text(
                              '-$savingsPercent%',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Widget _roundMiniAction({required IconData icon, required Color color, required Color bg}) {
  return Container(
    width: 46,
    height: 46,
    margin: const EdgeInsets.only(left: 8),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
    child: Icon(icon, color: color),
  );
}
