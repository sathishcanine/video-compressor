import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'pro_canvas_session.dart';

/// Main editor preview: mirrors Canvas (✓) framing — ratio, zoom, fill, pinch, tilt.
class ProCanvasEditorPreview extends StatelessWidget {
  const ProCanvasEditorPreview({
    super.key,
    required this.controller,
    required this.session,
    required this.onTap,
    this.watermark = true,
  });

  final VideoPlayerController controller;
  final ProCanvasSessionSettings session;
  final VoidCallback onTap;
  final bool watermark;

  @override
  Widget build(BuildContext context) {
    final ready = controller.value.isInitialized;
    final videoAr = ProCanvasLayout.videoAspect(controller);
    final canvasAr = session.resolvedCanvasAspect(videoAr);

    return LayoutBuilder(
      builder: (context, c) {
        final max = Size(c.maxWidth, c.maxHeight);
        final box = ProCanvasLayout.canvasBox(max, canvasAr);
        final cw = box.w;
        final ch = box.h;
        final contain = ProCanvasLayout.containVideo(cw, ch, videoAr);
        final scale = ProCanvasLayout.clampedVideoScale(
          cw: cw,
          ch: ch,
          videoAr: videoAr,
          tiltRad: session.tiltRadians,
          zoomSlider01: session.zoomSlider,
          fillExpandMode: session.fillExpandMode,
          pinchScale: session.pinchScale,
        );
        final panOffset = Offset(session.panNormX * cw, session.panNormY * ch);

        return GestureDetector(
          onTap: onTap,
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              child: ClipRect(
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: cw,
                  height: ch,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Colors.black),
                      Center(
                        child: Transform.translate(
                          offset: panOffset,
                          child: Transform.rotate(
                            angle: session.tiltRadians,
                            child: Transform.scale(
                              scale: scale,
                              alignment: Alignment.center,
                              child: SizedBox(
                                width: contain.bw,
                                height: contain.bh,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: ready
                                      ? FittedBox(
                                          fit: BoxFit.contain,
                                          child: SizedBox(
                                            width: videoAr * 100,
                                            height: 100,
                                            child: VideoPlayer(controller),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (watermark)
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Text(
                            'VidPress',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              shadows: const [
                                Shadow(blurRadius: 4, color: Colors.black54),
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
        );
      },
    );
  }
}
