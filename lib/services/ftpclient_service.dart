import 'dart:io';
import 'dart:convert';
import 'dart:async';

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

class FtpClientService {
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
    StreamSubscription? subscription;
    String buffer = '';
    final responseCompleter = <Completer<String>>[];

    try {
      onProgress?.call('Connecting to FTP server...', 0.1, null);

      // Connect to FTP server
      controlSocket = await Socket.connect(host, port);
      print('FTP: Connected to $host:$port');

      // Set up a single persistent listener
      subscription = controlSocket.listen(
        (data) {
          buffer += utf8.decode(data);

          // Process all complete responses in buffer
          while (buffer.contains('\r\n')) {
            final lineEnd = buffer.indexOf('\r\n');
            final response = buffer.substring(0, lineEnd);
            buffer = buffer.substring(lineEnd + 2);

            // Complete the next waiting response
            if (responseCompleter.isNotEmpty) {
              final completer = responseCompleter.removeAt(0);
              if (!completer.isCompleted) {
                completer.complete(response);
              }
            }
          }
        },
        onError: (error) {
          // Complete any waiting responses with error
          for (final completer in responseCompleter) {
            if (!completer.isCompleted) {
              completer.completeError(error);
            }
          }
          responseCompleter.clear();
        },
      );

      // Helper function to get next response
      Future<String> getNextResponse() {
        final completer = Completer<String>();
        responseCompleter.add(completer);
        return completer.future.timeout(Duration(seconds: 30));
      }

      // Read welcome message
      String response = await getNextResponse();
      print('FTP: Server welcome: $response');

      onProgress?.call('Authenticating...', 0.2, null);

      // Send username
      controlSocket.write('USER $username\r\n');
      response = await getNextResponse();
      print('FTP: USER response: $response');

      // Send password
      controlSocket.write('PASS $password\r\n');
      response = await getNextResponse();
      print('FTP: PASS response: $response');

      if (!response.startsWith('230')) {
        throw Exception('Authentication failed: $response');
      }

      // Set binary mode for proper file transfer
      controlSocket.write('TYPE I\r\n');
      response = await getNextResponse();
      print('FTP: TYPE I response: $response');

      onProgress?.call('Setting up data connection...', 0.3, null);

      // Set passive mode if requested
      if (passiveMode) {
        controlSocket.write('PASV\r\n');
        response = await getNextResponse();
        print('FTP: PASV response: $response');

        if (!response.startsWith('227')) {
          throw Exception('Passive mode failed: $response');
        }

        // Parse passive response to get data connection details
        final pasvMatch = RegExp(r'\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)')
            .firstMatch(response);
        if (pasvMatch == null) {
          throw Exception('Could not parse passive response: $response');
        }

        final ip =
            '${pasvMatch.group(1)}.${pasvMatch.group(2)}.${pasvMatch.group(3)}.${pasvMatch.group(4)}';
        final port = int.parse(pasvMatch.group(5)!) * 256 +
            int.parse(pasvMatch.group(6)!);

        print('FTP: Data connection to $ip:$port');
        dataSocket = await Socket.connect(ip, port);
      }

      onProgress?.call('Preparing file upload...', 0.4, null);

      // Check if local file exists
      final localFile = File(localFilePath);
      if (!await localFile.exists()) {
        throw Exception('Local file does not exist: $localFilePath');
      }

      final fileName = remoteFilePath.split('/').last;
      final fileSize = await localFile.length();
      print('FTP: Uploading $localFilePath as $fileName (${fileSize} bytes)');

      // Send STOR command
      controlSocket.write('STOR $fileName\r\n');
      response = await getNextResponse();
      print('FTP: STOR response: $response');

      if (!response.startsWith('150')) {
        throw Exception('STOR command failed: $response');
      }

      onProgress?.call('Uploading file...', 0.5, null);

      // Upload file data
      final fileBytes = await localFile.readAsBytes();
      print('FTP: Sending ${fileBytes.length} bytes...');
      dataSocket!.add(fileBytes);
      await dataSocket.flush();
      dataSocket.close();

      onProgress?.call('Finalizing upload...', 0.8, null);

      // Wait for transfer complete response
      response = await getNextResponse();
      print('FTP: Transfer complete: $response');

      if (!response.startsWith('226')) {
        throw Exception('File transfer failed: $response');
      }

      print('FTP: ✅ Upload successful - server confirmed file transfer');
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
      subscription?.cancel();
      dataSocket?.close();
      if (controlSocket != null) {
        try {
          controlSocket.write('QUIT\r\n');
          // Don't wait for QUIT response since we're closing anyway
          controlSocket.close();
          print('FTP: Disconnected from $host');
        } catch (e) {
          print('FTP: Error during disconnect: $e');
        }
      }
    }
  }
}
