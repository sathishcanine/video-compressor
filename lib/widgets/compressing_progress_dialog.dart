import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class CompressingProgressDialog extends StatefulWidget {
  const CompressingProgressDialog({super.key, required this.presetLabel});

  final String presetLabel;

  @override
  State<CompressingProgressDialog> createState() => _CompressingProgressDialogState();
}

class _CompressingProgressDialogState extends State<CompressingProgressDialog> {
  double _progress = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    const totalMs = 2600;
    const tick = 40;
    var elapsed = 0;
    _timer = Timer.periodic(const Duration(milliseconds: tick), (t) {
      elapsed += tick;
      final next = (elapsed / totalMs).clamp(0.0, 1.0);
      setState(() => _progress = next);
      if (elapsed >= totalMs) {
        t.cancel();
        if (mounted) Navigator.of(context).pop(true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_progress * 100).round();
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.videocam_rounded, color: AppColors.primary, size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              'Compressing Video',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Applying ${widget.presetLabel} preset...',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 22),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 10,
                backgroundColor: AppColors.background,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '$pct%',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
