// Pro editor — feature inventory (from InShot-style reference) & rollout phases.
//
// ═══════════════════════════════════════════════════════════════════════════
// COMPLETE FEATURE INVENTORY
// ═══════════════════════════════════════════════════════════════════════════
//
// A) CHROME / SHELL
//    • Top bar: Back, Zoom/Help (search+), Export
//    • Promo / ad banner strip below top bar
//    • Dark theme shell
//
// B) PREVIEW
//    • Large video preview (letterboxed)
//    • Branded corner watermark
//    • (Optional) Tap preview to play/pause
//
// C) PLAYBACK BAR (under preview)
//    • Undo / Redo (history stack; disabled when empty)
//    • Play / Pause
//    • Fullscreen preview
//    • (InShot) extra menu chevron — optional
//
// D) PRIMARY HORIZONTAL RIBBON (scrollable tools — icon + label)
//    Main strip:     Canvas, Audio, Sticker, Text, Effect, Filter, PIP
//    Clip tools:     Precut, Split, Delete, Volume, Background, Speed
//    Motion / AI:    Animation, AI Cut, Voice Enhance, Crop, Switch
//    Pro image:      Enhance, Stabilizer, Cutout, Mask, Templates, Opacity, Reverse
//    Clip advanced:  Replace, Voice Effect, Duplicate, Rotate, Freeze, Capture,
//                    Ease, Flip, Trim
//
// E) TIMELINE / TRACKS
//    • Red “+” add media (multi-clip later)
//    • Mute clip (toggle audio)
//    • Filmstrip thumbnails + yellow selection / white playhead
//    • Hint: “Select one track to edit.”
//    • Time ruler ticks (e.g. 00:00, 00:02, …)
//    • Scrub / seek by dragging playhead or tapping strip
//
// F) EXPORT PIPELINE (end state)
//    • Resolution, FPS, format, quality, save, share
//
// ═══════════════════════════════════════════════════════════════════════════
// ROLLOUT PLAN (implement one by one)
// ═══════════════════════════════════════════════════════════════════════════
//
// Phase 1 — InShot layout shell + ribbon + timeline seek + thumbnails + mute +
//           fullscreen + playback bar (undo/redo disabled).
// Phase 2 — Undo/redo for destructive preview ops (edit command stack).
// Phase 3 — Trim/Precut, Crop (aspect + zoom + pan), Split (at playhead), Speed, Volume,
//           Audio (music bed under clip), Rotate/flip, Reverse, Duplicate, Delete; FFmpeg.
// Phase 4 — Multi-clip timeline UI; append (+) joins two files (mixed audio: silent pad).
//           Transitions & multi-segment strip UI later.
// Phase 5 — Overlays: Text, Sticker, PIP, Filter, Effect (layers + export comp).
// Phase 6 — Audio track: music, duck, voice-over, extract.
// Phase 7 — Canvas: ratio, BG, blur; Mask, Chroma, Templates.
// Phase 8 — Export sheet + integration with compression / gallery.
//
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

/// Short explanation when a ribbon tool is not implemented yet (honest UX).
String proRibbonComingSoonMessage(String id) {
  switch (id) {
    case 'canvas':
      return 'Change aspect ratio, fit, and background fill. Planned for a later release. '
          'Use Rotate or Trim today to adjust framing.';
    case 'background':
      return 'Solid, blur, or image behind the video. Planned with Canvas. '
          'Trim and export cover the current workflow.';
    case 'audio':
      return 'Background music under the clip is available from the Audio tool on the ribbon. '
          'Separate voice-over tracks and ducking are planned for a later update.';
    case 'sticker':
    case 'text':
    case 'pip':
      return 'Stickers, text, and picture-in-picture are overlay layers. '
          'They need a composition export pipeline — planned for a future phase.';
    case 'effect':
    case 'filter':
    case 'animation':
    case 'opacity':
      return 'Visual effects, filters, motion, and clip opacity need layered rendering and export. Not available in this build.';
    case 'ai_cut':
      return 'Automatic cutting from AI needs a cloud or on-device model. Not wired up yet.';
    case 'voice_enhance':
    case 'voice_fx':
      return 'Voice cleanup and character effects need dedicated audio DSP. Not available yet.';
    case 'crop':
      return 'Free-draw crop handles are planned. Use the Crop tool on the ribbon for aspect presets, zoom, and pan.';
    case 'switch':
      return 'Angle switch and reframing shortcuts are planned. Use Crop, Rotate, or Trim for now.';
    case 'enhance':
    case 'stabilizer':
    case 'cutout':
    case 'mask':
      return 'Quality enhance, stabilization, cutout, and masks need heavier processing pipelines. Coming later.';
    case 'templates':
      return 'Template layouts are planned as preset projects with text and media slots.';
    case 'freeze':
    case 'capture':
    case 'ease':
      return 'Freeze frame, keyframe easing, and frame grab need timeline keyframes. Not in this build yet.';
    default:
      return 'This ribbon option is not implemented in the current app version. '
          'See the list below for tools that work today.';
  }
}

/// Shown under every "coming soon" sheet so users know what actually runs.
const String kProEditorAvailableNowLine =
    'Working now: Trim, Precut, Crop, Split, Speed, Volume, Audio (music bed), Rotate, Flip, Reverse, Duplicate, '
    'Replace, Delete (leave editor), Export, Join clips (+), timeline mute & seek.';

/// Single tool in the bottom horizontal ribbon (InShot-style).
class ProRibbonToolDef {
  const ProRibbonToolDef({
    required this.id,
    required this.label,
    required this.icon,
    this.showDividerBefore = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final bool showDividerBefore;
}

/// Ordered ribbon matching reference screenshots (one continuous strip).
const kProInShotRibbonTools = <ProRibbonToolDef>[
  ProRibbonToolDef(id: 'canvas', label: 'Canvas', icon: Icons.crop_square_rounded),
  ProRibbonToolDef(id: 'audio', label: 'Audio', icon: Icons.library_music_rounded),
  ProRibbonToolDef(id: 'sticker', label: 'Sticker', icon: Icons.emoji_emotions_outlined),
  ProRibbonToolDef(id: 'text', label: 'Text', icon: Icons.text_fields_rounded),
  ProRibbonToolDef(id: 'effect', label: 'Effect', icon: Icons.auto_awesome_rounded),
  ProRibbonToolDef(id: 'filter', label: 'Filter', icon: Icons.filter_rounded),
  ProRibbonToolDef(id: 'pip', label: 'PIP', icon: Icons.picture_in_picture_alt_rounded),
  ProRibbonToolDef(
    id: 'precut',
    label: 'Precut',
    icon: Icons.content_cut_rounded,
    showDividerBefore: true,
  ),
  ProRibbonToolDef(id: 'split', label: 'Split', icon: Icons.call_split_rounded),
  ProRibbonToolDef(id: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded),
  ProRibbonToolDef(id: 'volume', label: 'Volume', icon: Icons.volume_up_rounded),
  ProRibbonToolDef(id: 'background', label: 'Background', icon: Icons.texture_rounded),
  ProRibbonToolDef(id: 'speed', label: 'Speed', icon: Icons.speed_rounded),
  ProRibbonToolDef(id: 'animation', label: 'Animation', icon: Icons.animation_rounded),
  ProRibbonToolDef(id: 'ai_cut', label: 'AI Cut', icon: Icons.auto_fix_high_rounded),
  ProRibbonToolDef(id: 'voice_enhance', label: 'Voice Enhance', icon: Icons.mic_rounded),
  ProRibbonToolDef(id: 'crop', label: 'Crop', icon: Icons.crop_rounded),
  ProRibbonToolDef(id: 'switch', label: 'Switch', icon: Icons.swap_calls_rounded),
  ProRibbonToolDef(id: 'enhance', label: 'Enhance', icon: Icons.hd_rounded),
  ProRibbonToolDef(id: 'stabilizer', label: 'Stabilizer', icon: Icons.video_stable_rounded),
  ProRibbonToolDef(id: 'cutout', label: 'Cutout', icon: Icons.person_outline_rounded),
  ProRibbonToolDef(id: 'mask', label: 'Mask', icon: Icons.crop_square_rounded),
  ProRibbonToolDef(id: 'templates', label: 'Templates', icon: Icons.dashboard_customize_outlined),
  ProRibbonToolDef(id: 'opacity', label: 'Opacity', icon: Icons.opacity_rounded),
  ProRibbonToolDef(id: 'reverse', label: 'Reverse', icon: Icons.replay_rounded),
  ProRibbonToolDef(id: 'replace', label: 'Replace', icon: Icons.switch_video_rounded),
  ProRibbonToolDef(id: 'voice_fx', label: 'Voice Effect', icon: Icons.record_voice_over_rounded),
  ProRibbonToolDef(id: 'duplicate', label: 'Duplicate', icon: Icons.copy_all_rounded),
  ProRibbonToolDef(id: 'rotate', label: 'Rotate', icon: Icons.rotate_right_rounded),
  ProRibbonToolDef(id: 'freeze', label: 'Freeze', icon: Icons.ac_unit_rounded),
  ProRibbonToolDef(id: 'capture', label: 'Capture', icon: Icons.center_focus_strong_rounded),
  ProRibbonToolDef(id: 'ease', label: 'Ease', icon: Icons.timeline_rounded),
  ProRibbonToolDef(id: 'flip', label: 'Flip', icon: Icons.flip_rounded),
  ProRibbonToolDef(id: 'trim', label: 'Trim', icon: Icons.view_timeline_rounded),
];
