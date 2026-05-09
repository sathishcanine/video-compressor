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
    required this.videoPath,
    required this.savingsPercent,
    required this.originalMb,
    required this.compressedMb,
    required this.onSaveToGallery,
  });

  final CompressionPreset preset;
  final bool isCustom;
  final String customSubtitle;
  final String videoPath;
  final int savingsPercent;
  final double originalMb;
  final double compressedMb;
  final Future<void> Function() onSaveToGallery;

  @override
  State<CompressionResultScreen> createState() => _CompressionResultScreenState();
}

class _CompressionResultScreenState extends State<CompressionResultScreen> {
  static const double _thumbnailWidthFactor = 0.5;

  VideoPlayerController? _preview;
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
    _preview = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) async {
        final c = _preview;
        if (c == null || !mounted) return;
        await c.setVolume(0);
        await c.pause();
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
    _preview?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final savedMb = (widget.originalMb - widget.compressedMb).clamp(0, double.infinity);
    final subtitle = widget.isCustom ? widget.customSubtitle : widget.preset.name;
    final controller = _preview;

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
      body: controller == null || !controller.value.isInitialized
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
                    Align(
                      alignment: Alignment.center,
                      child: FractionallySizedBox(
                        widthFactor: _thumbnailWidthFactor,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: AspectRatio(
                            aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                VideoPlayer(controller),
                                Center(
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.35),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                                  ),
                                ),
                                Positioned(
                                  right: 8,
                                  bottom: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: AppColors.success,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.trending_down_rounded, color: Colors.white, size: 14),
                                        const SizedBox(width: 4),
                                        Text(
                                          '-${widget.savingsPercent}% smaller',
                                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 11,
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
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
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
