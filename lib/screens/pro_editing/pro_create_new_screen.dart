import 'package:flutter/material.dart';

import 'pro_studio_theme.dart';
import 'pro_video_editor_screen.dart';

/// Full-screen launcher (no bottom nav) — CREATE NEW with Video / Photo / Collage.
class ProCreateNewScreen extends StatelessWidget {
  const ProCreateNewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(gradient: ProStudioTheme.backgroundGradient),
        child: Stack(
          children: [
            ..._blossomDecor(),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Pro settings — coming soon.'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          icon: Icon(Icons.settings_outlined, color: Colors.white.withValues(alpha: 0.95)),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 22, top: 8),
                    child: Text(
                      'VidPress Pro',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: ProStudioTheme.brandText,
                            letterSpacing: -0.5,
                          ),
                    ),
                  ),
                  const Spacer(flex: 2),
                  Padding(
                    padding: const EdgeInsets.only(left: 24, bottom: 12),
                    child: Text(
                      'CREATE NEW',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: ProStudioTheme.createLabel,
                          ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 36),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _CreateCircleButton(
                            icon: Icons.movie_creation_rounded,
                            label: 'Video',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const ProVideoEditorScreen(),
                                ),
                              );
                            },
                          ),
                          _CreateCircleButton(
                            icon: Icons.landscape_rounded,
                            label: 'Photo',
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Photo editor — coming soon.'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                          ),
                          _CreateCircleButton(
                            icon: Icons.grid_view_rounded,
                            label: 'Collage',
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Collage — coming soon.'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _blossomDecor() {
    return [
      _floral(0.08, top: 120, left: 20, size: 56, rot: -0.2),
      _floral(0.1, top: 200, right: 30, size: 48, rot: 0.35),
      _floral(0.07, top: 320, left: 40, size: 44, rot: 0.15),
      _floral(0.09, bottom: 220, right: 24, size: 52, rot: -0.25),
      _floral(0.06, bottom: 300, left: 28, size: 40, rot: 0.4),
    ];
  }

  Widget _floral(
    double opacity, {
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double size,
    required double rot,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Transform.rotate(
        angle: rot,
        child: Opacity(
          opacity: opacity,
          child: Icon(Icons.filter_vintage_rounded, size: size, color: Colors.white),
        ),
      ),
    );
  }
}

class _CreateCircleButton extends StatelessWidget {
  const _CreateCircleButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: ProStudioTheme.circleButtonGradient,
                boxShadow: [
                  BoxShadow(
                    color: ProStudioTheme.buttonPink.withValues(alpha: 0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 34),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ProStudioTheme.pinkTop,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
