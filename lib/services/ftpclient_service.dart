import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class FtpUploadResult {
  final bool success;
  final String? error;
  final String? details;

  FtpUploadResult({
    required this.success,
    this.error,
    this.details,
  });
}

typedef FtpProgressCallback = void Function(
    String status, double progress, String? error);

/// Remote (and duplicate-copy) file name. An empty rename keeps the original.
/// A rename without an extension keeps the source extension.
String ftpTransferFileName(String sourcePath, String renameAs) {
  final original = p.basename(sourcePath);
  var custom = renameAs.trim();
  if (custom.isEmpty) return original;
  custom = p.basename(custom.replaceAll('\\', '/'));
  if (custom.isEmpty) return original;
  if (p.extension(custom).isEmpty && p.extension(original).isNotEmpty) {
    return '$custom${p.extension(original)}';
  }
  return custom;
}

/// Copies [sourcePath] into [folder] as [fileName].
/// Returns null when the folder is blank or the copy succeeds, otherwise the error.
Future<String?> copyFtpDuplicate({
  required String sourcePath,
  required String folder,
  required String fileName,
}) async {
  final dirPath = folder.trim();
  if (dirPath.isEmpty) return null;
  try {
    final destDir = Directory(dirPath);
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }
    final dest = p.join(destDir.path, fileName);
    final src = File(sourcePath);
    if (p.normalize(src.absolute.path) == p.normalize(File(dest).absolute.path)) {
      return null;
    }
    await src.copy(dest);
    print('FTP: Duplicate copy → $dest');
    return null;
  } catch (e) {
    print('FTP: Duplicate copy failed: $e');
    return e.toString();
  }
}

class FtpClientService {
  /// Connect and authenticate only — no data transfer.
  static Future<FtpUploadResult> testConnection({
    required String host,
    required String username,
    required String password,
    int port = 21,
    String remotePath = '',
    bool passiveMode = true,
  }) async {
    Socket? controlSocket;
    _FtpControlSession? session;

    try {
      controlSocket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 15),
      );
      session = _FtpControlSession(controlSocket);

      var response = await session.nextReply();
      if (!response.startsWith('220')) {
        throw Exception('Unexpected welcome: $response');
      }

      controlSocket.write('USER $username\r\n');
      response = await session.nextReply();
      controlSocket.write('PASS $password\r\n');
      response = await session.nextReply();
      if (!response.startsWith('230')) {
        throw Exception('Authentication failed: $response');
      }

      final path = remotePath.trim();
      if (path.isNotEmpty && path != '/') {
        controlSocket.write('CWD $path\r\n');
        response = await session.nextReply();
        if (!response.startsWith('250')) {
          throw Exception('Remote path not found: $response');
        }
      }

      if (passiveMode) {
        controlSocket.write('PASV\r\n');
        response = await session.nextReply();
        if (!response.startsWith('227')) {
          throw Exception('Passive mode failed: $response');
        }
      }

      return FtpUploadResult(
        success: true,
        details: passiveMode
            ? 'Connected and authenticated (passive OK).'
            : 'Connected and authenticated.',
      );
    } catch (e) {
      return FtpUploadResult(
        success: false,
        error: 'Connection failed',
        details: e.toString(),
      );
    } finally {
      await session?.close();
      if (controlSocket != null) {
        try {
          controlSocket.write('QUIT\r\n');
          controlSocket.close();
        } catch (_) {}
      }
    }
  }

  static Future<FtpUploadResult> uploadFile({
    required String host,
    required String username,
    required String password,
    required String localFilePath,
    required String remoteFilePath,
    int port = 21,
    bool passiveMode = true,
    FtpProgressCallback? onProgress,
  }) async {
    FtpUploadResult? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      last = await _uploadOnce(
        host: host,
        username: username,
        password: password,
        localFilePath: localFilePath,
        remoteFilePath: remoteFilePath,
        port: port,
        passiveMode: passiveMode,
        onProgress: onProgress,
      );
      if (last.success) return last;
      final details = last.details ?? '';
      final retryable = details.contains('TimeoutException') ||
          details.contains('SocketException') ||
          details.contains('Connection reset') ||
          details.contains('Connection refused') ||
          details.contains('FTP connection closed') ||
          details.contains('530') ||
          details.contains('Authentication failed');
      if (!retryable || attempt == 2) return last;
      print('FTP: retrying after $details');
      onProgress?.call('Retrying upload…', 0.0, null);
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return last ??
        FtpUploadResult(success: false, error: 'Upload failed');
  }

  static Future<FtpUploadResult> _uploadOnce({
    required String host,
    required String username,
    required String password,
    required String localFilePath,
    required String remoteFilePath,
    required int port,
    required bool passiveMode,
    FtpProgressCallback? onProgress,
  }) async {
    Socket? controlSocket;
    Socket? dataSocket;
    _FtpControlSession? session;

    try {
      if (!passiveMode) {
        throw Exception(
          'Active FTP is not supported. Turn Passive mode on in FTP settings.',
        );
      }

      onProgress?.call('Connecting to FTP server...', 0.0, null);

      controlSocket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 15),
      );
      print('FTP: Connected to $host:$port');
      session = _FtpControlSession(controlSocket);

      String response = await session.nextReply();
      print('FTP: Server welcome: $response');
      if (!response.startsWith('220')) {
        throw Exception('Unexpected welcome: $response');
      }

      onProgress?.call('Authenticating...', 0.0, null);

      controlSocket.write('USER $username\r\n');
      response = await session.nextReply();
      print('FTP: USER response: $response');

      controlSocket.write('PASS $password\r\n');
      response = await session.nextReply();
      print('FTP: PASS response: $response');

      if (!response.startsWith('230')) {
        throw Exception('Authentication failed: $response');
      }

      controlSocket.write('TYPE I\r\n');
      response = await session.nextReply();
      print('FTP: TYPE I response: $response');

      final localFile = File(localFilePath);
      if (!await localFile.exists()) {
        throw Exception('Local file does not exist: $localFilePath');
      }

      final normalizedRemote = remoteFilePath.replaceAll('\\', '/');
      final slash = normalizedRemote.lastIndexOf('/');
      final remoteDir = slash > 0 ? normalizedRemote.substring(0, slash) : '';
      final fileName = slash >= 0
          ? normalizedRemote.substring(slash + 1)
          : normalizedRemote;
      if (fileName.isEmpty) {
        throw Exception('Remote file name is empty: $remoteFilePath');
      }

      // Open the data port only after the directory change. Opening PASV first
      // lets the server time out the data socket while CWD is still running.
      if (remoteDir.isNotEmpty && remoteDir != '.') {
        controlSocket.write('CWD $remoteDir\r\n');
        response = await session.nextReply();
        print('FTP: CWD $remoteDir → $response');
        if (!response.startsWith('250')) {
          throw Exception(
              'Could not open remote folder "$remoteDir": $response');
        }
      }

      onProgress?.call('Setting up data connection...', 0.0, null);

      controlSocket.write('PASV\r\n');
      response = await session.nextReply();
      print('FTP: PASV response: $response');

      if (!response.startsWith('227')) {
        throw Exception('Passive mode failed: $response');
      }

      final pasvMatch = RegExp(r'\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)')
          .firstMatch(response);
      if (pasvMatch == null) {
        throw Exception('Could not parse passive response: $response');
      }

      final pasvIp =
          '${pasvMatch.group(1)}.${pasvMatch.group(2)}.${pasvMatch.group(3)}.${pasvMatch.group(4)}';
      final dataPort = int.parse(pasvMatch.group(5)!) * 256 +
          int.parse(pasvMatch.group(6)!);
      // Servers behind NAT often advertise a private address the client
      // cannot reach. Use the host we already connected to in that case.
      final dataHost =
          _looksPrivate(pasvIp) && !_looksPrivate(host) ? host : pasvIp;

      print('FTP: Data connection to $dataHost:$dataPort');
      dataSocket = await Socket.connect(
        dataHost,
        dataPort,
        timeout: const Duration(seconds: 15),
      );

      onProgress?.call('Preparing file upload...', 0.0, null);

      final fileSize = await localFile.length();
      print('FTP: Uploading $localFilePath as $fileName ($fileSize bytes)');

      controlSocket.write('STOR $fileName\r\n');
      response = await session.nextReply();
      print('FTP: STOR response: $response');

      if (!response.startsWith('150') && !response.startsWith('125')) {
        throw Exception('STOR command failed: $response');
      }

      onProgress?.call('Uploading file...', 0.0, null);

      final fileBytes = await localFile.readAsBytes();
      final totalBytes = fileBytes.length;
      print('FTP: Sending $totalBytes bytes...');

      const chunkSize = 32768;
      var uploadedBytes = 0;

      for (var i = 0; i < fileBytes.length; i += chunkSize) {
        final end = (i + chunkSize < fileBytes.length)
            ? i + chunkSize
            : fileBytes.length;
        dataSocket.add(fileBytes.sublist(i, end));

        uploadedBytes += end - i;
        final progress = totalBytes == 0 ? 1.0 : uploadedBytes / totalBytes;
        onProgress?.call('Uploading file...', progress, null);
      }

      await dataSocket.flush();
      await dataSocket.close();
      dataSocket = null;

      onProgress?.call('Finalizing upload...', 1.0, null);

      response = await session.nextReply();
      print('FTP: Transfer complete: $response');

      if (!response.startsWith('226')) {
        throw Exception('File transfer failed: $response');
      }

      print('FTP: Upload successful - server confirmed file transfer');
      onProgress?.call('Upload completed successfully!', 1.0, null);

      return FtpUploadResult(
        success: true,
        error: null,
        details: 'File uploaded successfully: $fileName',
      );
    } catch (e) {
      final errorMsg = e.toString();
      print('FTP: Upload error: $errorMsg');
      onProgress?.call('Upload failed', 0.0, errorMsg);
      return FtpUploadResult(
        success: false,
        error: 'Upload failed',
        details: errorMsg,
      );
    } finally {
      await session?.close();
      dataSocket?.destroy();
      if (controlSocket != null) {
        try {
          controlSocket.write('QUIT\r\n');
          await controlSocket.flush();
          await controlSocket.close();
          print('FTP: Disconnected from $host');
        } catch (e) {
          controlSocket.destroy();
          print('FTP: Error during disconnect: $e');
        }
      }
    }
  }
}

bool _looksPrivate(String host) {
  final ip = host.trim().toLowerCase();
  if (ip == 'localhost' || ip.startsWith('127.')) return true;
  if (ip.startsWith('10.') || ip.startsWith('192.168.')) return true;
  final match = RegExp(r'^172\.(\d+)\.').firstMatch(ip);
  if (match != null) {
    final second = int.tryParse(match.group(1)!) ?? 0;
    if (second >= 16 && second <= 31) return true;
  }
  return false;
}

/// Reads complete FTP replies. Lines that arrive before anyone is waiting are
/// kept, and multi-line replies (220- … 220 ) are returned as one string.
class _FtpControlSession {
  _FtpControlSession(Socket socket) {
    _sub = socket.listen(
      (data) {
        _buffer += utf8.decode(data, allowMalformed: true);
        _drain();
      },
      onError: (Object error) {
        print('FTP: Socket error: $error');
        _fail(error);
      },
      onDone: () {
        print('FTP: Connection closed');
        _fail(StateError('FTP connection closed'));
      },
    );
  }

  final List<String> _lines = [];
  final List<Completer<String>> _waiters = [];
  String _buffer = '';
  Object? _error;
  StreamSubscription<List<int>>? _sub;

  void _drain() {
    while (_buffer.contains('\n')) {
      final index = _buffer.indexOf('\n');
      var line = _buffer.substring(0, index);
      _buffer = _buffer.substring(index + 1);
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      if (line.isEmpty) continue;
      print('FTP: Received: $line');
      if (_waiters.isNotEmpty) {
        final waiter = _waiters.removeAt(0);
        if (!waiter.isCompleted) waiter.complete(line);
      } else {
        _lines.add(line);
      }
    }
  }

  void _fail(Object error) {
    _error ??= error;
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) waiter.completeError(error);
    }
    _waiters.clear();
  }

  Future<String> _nextLine() {
    if (_lines.isNotEmpty) return Future.value(_lines.removeAt(0));
    if (_error != null) return Future.error(_error!);
    final completer = Completer<String>();
    _waiters.add(completer);
    return completer.future.timeout(const Duration(seconds: 30),
        onTimeout: () {
      _waiters.remove(completer);
      throw TimeoutException('FTP response timeout');
    });
  }

  Future<String> nextReply() async {
    final first = await _nextLine();
    if (first.length < 4 || first[3] != '-') return first;
    final code = first.substring(0, 3);
    final buf = StringBuffer(first);
    while (true) {
      final line = await _nextLine();
      buf.write('\n');
      buf.write(line);
      if (line.startsWith('$code ')) return buf.toString();
    }
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
  }
}
