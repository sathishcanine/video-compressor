import 'package:flutter/foundation.dart';

class CompressionHistoryEntry {
  CompressionHistoryEntry({
    required this.at,
    required this.presetLabel,
    required this.fileName,
    required this.savedPercent,
    required this.savedMb,
  });

  final DateTime at;
  final String presetLabel;
  final String fileName;
  final int savedPercent;
  final double savedMb;
}

final class CompressionHistory extends ChangeNotifier {
  CompressionHistory._();
  static final CompressionHistory instance = CompressionHistory._();

  final List<CompressionHistoryEntry> entries = [];

  void add(CompressionHistoryEntry e) {
    entries.insert(0, e);
    notifyListeners();
  }
}
