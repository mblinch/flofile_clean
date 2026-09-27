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
      at: DateTime.tryParse(json['at']?.toString() ?? '') ?? DateTime.now(),
      fileName: json['fileName']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      profile: json['profile']?.toString() ?? '',
      success: json['success'] == true,
      error: json['error']?.toString(),
    );
  }
}
