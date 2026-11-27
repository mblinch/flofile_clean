import 'caption_transfer_payload.dart';

/// One saved caption's user-built portion (roster / verb / opponent / period).
///
/// Template text (dateline, venue, credit) is intentionally omitted — the
/// current photo regenerates that when a history row is applied.
class CaptionHistoryEntry {
  const CaptionHistoryEntry({
    required this.body,
    required this.savedAt,
    this.playersText = '',
    this.verbText = '',
    this.clicks,
    this.imagePath,
  });

  /// User-built caption body only, e.g.
  /// "Auston Matthews #34 shoots against Buffalo Sabres during the first period".
  final String body;

  /// Lead (player / team names) for highlight styling.
  final String playersText;

  /// Verb / action core for highlight styling.
  final String verbText;

  /// Buttons that produced [body], so apply can rebuild with the current template.
  final CaptionClickSnapshot? clicks;

  /// Photo this caption was saved on — shown as a thumb in the history menu.
  final String? imagePath;

  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'body': body,
        'playersText': playersText,
        'verbText': verbText,
        'savedAt': savedAt.toIso8601String(),
        if (clicks != null) 'clicks': clicks!.toJson(),
        if (imagePath != null && imagePath!.trim().isNotEmpty)
          'imagePath': imagePath,
      };

  factory CaptionHistoryEntry.fromJson(Map<String, dynamic> json) {
    final savedRaw = json['savedAt']?.toString();
    final path = json['imagePath']?.toString().trim();
    return CaptionHistoryEntry(
      body: (json['body'] ?? '').toString(),
      playersText: (json['playersText'] ?? '').toString(),
      verbText: (json['verbText'] ?? '').toString(),
      clicks: CaptionClickSnapshot.fromJson(json['clicks']),
      imagePath: path == null || path.isEmpty ? null : path,
      savedAt: savedRaw == null || savedRaw.isEmpty
          ? DateTime.now()
          : (DateTime.tryParse(savedRaw) ?? DateTime.now()),
    );
  }
}

/// Elapsed time label matching the action-bar mock (`0:12`, `1:48`, `3h`).
String formatCaptionHistoryAgo(DateTime savedAt, [DateTime? now]) {
  final elapsed = (now ?? DateTime.now()).difference(savedAt);
  if (elapsed.isNegative) return '0:00';
  if (elapsed.inHours >= 24) {
    final days = elapsed.inDays.clamp(1, 99);
    return '${days}d';
  }
  if (elapsed.inHours >= 1) {
    return '${elapsed.inHours}h';
  }
  final minutes = elapsed.inMinutes;
  final seconds = elapsed.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
