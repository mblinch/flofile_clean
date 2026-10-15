import 'dart:io';

/// Start of this app process. The history panel shows transfers from this
/// run only. Persisted history stays on disk for sent-state restore.
///
/// Computed from process uptime so a reload cannot move the cutoff forward
/// and hide uploads that already happened.
DateTime ftpSessionStartedAt() {
  return _ftpSessionStartedAt ??= _processStartedAt();
}

DateTime? _ftpSessionStartedAt;

DateTime _processStartedAt() {
  final elapsed = _processElapsed();
  if (elapsed == null) return DateTime.now();
  // etime is truncated to seconds; include that second.
  return DateTime.now().subtract(elapsed + const Duration(seconds: 1));
}

Duration? _processElapsed() {
  if (!Platform.isMacOS && !Platform.isLinux) return null;
  try {
    final result = Process.runSync('ps', ['-o', 'etime=', '-p', '$pid']);
    if (result.exitCode != 0) return null;
    return parseProcessEtime(result.stdout.toString());
  } catch (_) {
    return null;
  }
}

/// Parses `ps -o etime`: `mm:ss`, `hh:mm:ss`, or `dd-hh:mm:ss`.
Duration? parseProcessEtime(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  var days = 0;
  var clock = text;
  final daySplit = text.split('-');
  if (daySplit.length == 2) {
    final parsedDays = int.tryParse(daySplit[0]);
    if (parsedDays == null) return null;
    days = parsedDays;
    clock = daySplit[1];
  } else if (daySplit.length != 1) {
    return null;
  }
  final parts = clock.split(':');
  if (parts.any((part) => int.tryParse(part.trim()) == null)) return null;
  final numbers = parts.map((part) => int.parse(part.trim())).toList();
  if (numbers.length == 2) {
    return Duration(days: days, minutes: numbers[0], seconds: numbers[1]);
  }
  if (numbers.length == 3) {
    return Duration(
      days: days,
      hours: numbers[0],
      minutes: numbers[1],
      seconds: numbers[2],
    );
  }
  return null;
}

class FtpHistoryEntry {
  const FtpHistoryEntry({
    required this.at,
    required this.fileName,
    required this.path,
    required this.profile,
    required this.success,
    this.error,
  });

  final DateTime at;
  final String fileName;
  final String path;
  final String profile;
  final bool success;
  final String? error;

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'fileName': fileName,
        'path': path,
        'profile': profile,
        'success': success,
        if (error != null && error!.isNotEmpty) 'error': error,
      };

  factory FtpHistoryEntry.fromJson(Map<String, dynamic> json) {
    return FtpHistoryEntry(
      at: DateTime.tryParse(json['at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      fileName: json['fileName']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      profile: json['profile']?.toString() ?? '',
      success: json['success'] == true,
      error: json['error']?.toString(),
    );
  }
}
