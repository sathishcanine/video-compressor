import 'package:flutter/material.dart';

import '../data/history_store.dart';
import '../theme/app_colors.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'History',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'Recently compressed videos',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListenableBuilder(
                listenable: CompressionHistory.instance,
                builder: (context, _) {
                  final items = CompressionHistory.instance.entries;
                  if (items.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_rounded, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.35)),
                          const SizedBox(height: 12),
                          Text(
                            'No compressions yet',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Your finished jobs will show up here.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final e = items[i];
                      final time =
                          '${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}';
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          title: Text(
                            e.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text('${e.presetLabel} • saved ${e.savedPercent}%'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '-${e.savedMb.toStringAsFixed(1)} MB',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.success,
                                ),
                              ),
                              Text(time, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
