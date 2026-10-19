/// Uploads to show in the history panel.
///
/// Tagged entries belong to one caption session. Untagged entries are older
/// saves from before sessions were marked: they stay visible only for the
/// session already open when that change landed, and only if that file is
/// still in the session. A new session ([sessionStartedAt] set) leaves them out.
List<FtpHistoryEntry> ftpHistoryForSession(
  List<FtpHistoryEntry> entries, {
  required String? sessionId,
  required DateTime? sessionStartedAt,
  required Set<String> imagePaths,
}) {
  return [
    for (final entry in entries)
      if (_entryInSession(
        entry,
        sessionId: sessionId,
        sessionStartedAt: sessionStartedAt,
        imagePaths: imagePaths,
      ))
        entry,
  ];
}

bool _entryInSession(
  FtpHistoryEntry entry, {
  required String? sessionId,
  required DateTime? sessionStartedAt,
  required Set<String> imagePaths,
}) {
  final tagged = entry.sessionId;
  if (tagged != null && tagged.isNotEmpty) {
    return sessionId != null && tagged == sessionId;
  }
  if (!imagePaths.contains(entry.path)) return false;
  if (sessionStartedAt == null) return true;
  return !entry.at.isBefore(sessionStartedAt);
}

class FtpHistoryEntry {
  const FtpHistoryEntry({
    required this.at,
    required this.fileName,
    required this.path,
    required this.profile,
    required this.success,
    this.error,
    this.sessionId,
  });

  final DateTime at;
  final String fileName;
  final String path;
  final String profile;
  final bool success;
  final String? error;
  final String? sessionId;

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'fileName': fileName,
        'path': path,
        'profile': profile,
        'success': success,
        if (error != null && error!.isNotEmpty) 'error': error,
        if (sessionId != null && sessionId!.isNotEmpty) 'sessionId': sessionId,
      };

  factory FtpHistoryEntry.fromJson(Map<String, dynamic> json) {
    final sessionId = json['sessionId']?.toString();
    return FtpHistoryEntry(
      at: DateTime.tryParse(json['at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      fileName: json['fileName']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      profile: json['profile']?.toString() ?? '',
      success: json['success'] == true,
      error: json['error']?.toString(),
      sessionId: sessionId == null || sessionId.isEmpty ? null : sessionId,
    );
  }
}
