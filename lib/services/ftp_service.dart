import 'dart:io';
import 'dart:convert';

// FTP Upload Result class
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

// FTP Progress Callback
typedef FtpProgressCallback = void Function(
    String status, double progress, String? error);

class FtpService {
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  /// Upload a file to FTP server with retry logic and reconnection handling
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
    Socket? controlSocket;
    Socket? dataSocket;
    int retryCount = 0;

    try {
      onProgress?.call('Connecting to FTP server...', 0.1, null);

      while (retryCount < _maxRetries) {
        try {
          // Connect to FTP server
          controlSocket = await Socket.connect(host, port);
          print('FTP: Connected to $host:$port');

          // Read welcome message
          final welcome = await _readResponse(controlSocket);
          print('FTP: Server welcome: $welcome');

          onProgress?.call('Connected to FTP server', 0.2, null);

          // Login
          await _sendCommand(controlSocket, 'USER $username');
          final userResponse = await _readResponse(controlSocket);
          print('FTP: USER response: $userResponse');

          await _sendCommand(controlSocket, 'PASS $password');
          final passResponse = await _readResponse(controlSocket);
          print('FTP: PASS response: $passResponse');

          if (!passResponse.startsWith('230')) {
            throw Exception('Login failed: $passResponse');
          }

          onProgress?.call('Logged in successfully', 0.3, null);

          // Set passive mode
          if (passiveMode) {
            await _sendCommand(controlSocket, 'PASV');
            final pasvResponse = await _readResponse(controlSocket);
            print('FTP: PASV response: $pasvResponse');

            if (pasvResponse.startsWith('227')) {
              final dataPort = _parsePasvResponse(pasvResponse);
              dataSocket = await Socket.connect(host, dataPort);
              print('FTP: Data connection established on port $dataPort');
            }
          }

          // Check if local file exists
          final localFile = File(localFilePath);
          if (!await localFile.exists()) {
            final error = 'Local file does not exist: $localFilePath';
            onProgress?.call('Error: File not found', 0.0, error);
            return FtpUploadResult(
              success: false,
              error: 'File not found',
              details: error,
            );
          }

          onProgress?.call('File found, preparing upload...', 0.4, null);

          // Start upload
          final remoteFileName = remoteFilePath.split('/').last;
          await _sendCommand(controlSocket, 'STOR $remoteFileName');
          final storResponse = await _readResponse(controlSocket);
          print('FTP: STOR response: $storResponse');

          if (!storResponse.startsWith('150')) {
            throw Exception('Upload command failed: $storResponse');
          }

          onProgress?.call('Uploading file...', 0.5, null);

          // Upload file data
          final fileBytes = await localFile.readAsBytes();
          dataSocket?.add(fileBytes);
          await dataSocket?.flush();
          await dataSocket?.close();

          // Wait for transfer complete
          final transferResponse = await _readResponse(controlSocket);
          print('FTP: Transfer complete: $transferResponse');

          if (!transferResponse.startsWith('226')) {
            throw Exception('Transfer failed: $transferResponse');
          }

          onProgress?.call('Upload completed successfully!', 1.0, null);

          return FtpUploadResult(
            success: true,
            error: null,
            details: 'File uploaded to: $remoteFileName',
          );
        } catch (e) {
          retryCount++;
          final errorMsg = e.toString();
          print('FTP: Upload attempt $retryCount failed: $errorMsg');

          if (retryCount >= _maxRetries) {
            onProgress?.call(
                'Upload failed after $retryCount attempts', 0.0, errorMsg);
            return FtpUploadResult(
              success: false,
              error: 'Upload failed',
              details: errorMsg,
            );
          }

          // Wait before retry
          await Future.delayed(_retryDelay);
        } finally {
          // Clean up connections
          await controlSocket?.close();
          await dataSocket?.close();
        }
      }

      return FtpUploadResult(
        success: false,
        error: 'Max retries exceeded',
        details: 'Failed to upload after $_maxRetries attempts',
      );
    } catch (e) {
      final errorMsg = e.toString();
      print('FTP: Fatal error: $errorMsg');
      onProgress?.call('Fatal error', 0.0, errorMsg);
      return FtpUploadResult(
        success: false,
        error: 'Fatal error',
        details: errorMsg,
      );
    }
  }

  /// Download a file from FTP server
  static Future<FtpUploadResult> downloadFile({
    required String host,
    required String username,
    required String password,
    required String localFilePath,
    required String remoteFilePath,
    int port = 21,
    bool passiveMode = true,
    FtpProgressCallback? onProgress,
  }) async {
    // Implementation similar to upload but with RETR command
    // This is a placeholder - implement if needed
    return FtpUploadResult(
      success: false,
      error: 'Download not implemented',
      details: 'Download functionality not yet implemented',
    );
  }

  /// List files in FTP directory
  static Future<List<String>> listFiles({
    required String host,
    required String username,
    required String password,
    String directory = '/',
    int port = 21,
    bool passiveMode = true,
  }) async {
    // Implementation for listing files
    // This is a placeholder - implement if needed
    return [];
  }

  // Helper methods
  static Future<void> _sendCommand(Socket socket, String command) async {
    socket.write('$command\r\n');
    print('FTP: Sent: $command');
  }

  static Future<String> _readResponse(Socket socket) async {
    final response = await socket
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    print('FTP: Received: $response');
    return response;
  }

  static int _parsePasvResponse(String response) {
    // Parse PASV response like "227 Entering Passive Mode (192,168,1,1,123,45)"
    final match =
        RegExp(r'\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)').firstMatch(response);
    if (match != null) {
      final port1 = int.parse(match.group(5)!);
      final port2 = int.parse(match.group(6)!);
      return port1 * 256 + port2;
    }
    throw Exception('Could not parse PASV response: $response');
  }
}
