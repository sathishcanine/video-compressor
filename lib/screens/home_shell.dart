import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'compress_screen.dart';
import 'history_screen.dart';
import 'pro_editing/pro_create_new_screen.dart';
import 'video_edit_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          CompressScreen(),
          VideoEditScreen(),
          HistoryScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 64,
        selectedIndex: _index,
        onDestinationSelected: (i) {
          if (i == 3) {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const ProCreateNewScreen(),
              ),
            );
            return;
          }
          setState(() => _index = i);
        },
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined, color: AppColors.textSecondary),
            selectedIcon: Icon(Icons.bolt_rounded, color: AppColors.primary),
            label: 'Compress',
          ),
          NavigationDestination(
            icon: Icon(Icons.movie_filter_outlined, color: AppColors.textSecondary),
            selectedIcon: Icon(Icons.movie_filter_rounded, color: AppColors.primary),
            label: 'Edit',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded, color: AppColors.textSecondary),
            selectedIcon: Icon(Icons.history_rounded, color: AppColors.primary),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined, color: AppColors.textSecondary),
            selectedIcon: Icon(Icons.auto_awesome, color: AppColors.primary),
            label: 'Pro',
          ),
        ],
      ),
    );
  }
}
