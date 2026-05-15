import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_logo.dart';

typedef CompressionJob = Future<String> Function(void Function(double progress01) onProgress);

class CompressingProgressDialog extends StatefulWidget {
  const CompressingProgressDialog({
    super.key,
    required this.presetLabel,
    required this.job,
  });

  final String presetLabel;
  final CompressionJob job;

  @override
  State<CompressingProgressDialog> createState() => _CompressingProgressDialogState();
}

class _CompressingProgressDialogState extends State<CompressingProgressDialog> {
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget
          .job((p) {
            if (mounted) {
              setState(() => _progress = p.clamp(0.0, 1.0));
            }
          })
          .then((path) {
            if (mounted) Navigator.of(context).pop<String?>(path);
          }, onError: (Object e, StackTrace _) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Compression failed: $e')),
            );
            Navigator.of(context).pop<String?>(null);
          });
    });
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
            const AppLogo(size: 64, borderRadius: 18),
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
                value: _progress <= 0.01 && _progress < 1 ? null : _progress.clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: AppColors.background,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _progress >= 1 ? '100%' : (_progress <= 0.01 ? 'Starting…' : '$pct%'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
